#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  sudo sdcard/prepare-rpi3b-arch64.sh /dev/sdX
  sudo sdcard/prepare-rpi3b-arch64.sh /dev/mmcblkN /path/to/ArchLinuxARM-rpi-aarch64-latest.tar.gz

This destroys the target device, creates:
  - /boot: 2 GiB FAT32
  - /:     remaining space, F2FS with 15% overprovisioning
           and extra_attr,inode_checksum,sb_checksum

It installs Arch Linux ARM aarch64 for Raspberry Pi, embeds mitamae, and enables
a one-shot first-boot service that runs this repository's mitamae role.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

part_name() {
  case "$1" in
    *[0-9]) printf '%sp%s' "$1" "$2" ;;
    *) printf '%s%s' "$1" "$2" ;;
  esac
}

wait_for_partitions() {
  dev="$1"
  for _ in $(seq 1 20); do
    partprobe "$dev" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    [ -b "$(part_name "$dev" 1)" ] && [ -b "$(part_name "$dev" 2)" ] && return 0
    sleep 1
  done
  return 1
}

render_template() {
  src="$1"
  dest="$2"
  boot_partuuid="$3"
  root_partuuid="$4"
  root_f2fs_options="$5"

  sed \
    -e "s|@BOOT_PARTUUID@|$boot_partuuid|g" \
    -e "s|@ROOT_PARTUUID@|$root_partuuid|g" \
    -e "s|@ROOT_F2FS_OPTIONS@|$root_f2fs_options|g" \
    "$src" > "$dest"
}

write_nodes_yml() {
  src="$1"
  dest="$2"
  boot_partuuid="$3"
  root_partuuid="$4"

  cat "$src" > "$dest"
  {
    printf '\n'
    printf 'boot_partuuid: "%s"\n' "$boot_partuuid"
    printf 'root_partuuid: "%s"\n' "$root_partuuid"
  } >> "$dest"
}

configure_target_initramfs() {
  target="$1"

  if [ -f "$target/etc/mkinitcpio.conf" ]; then
    sed -i -E \
      -e 's/^MODULES=\(([^)]*)\)/MODULES=(f2fs \1)/' \
      -e 's/^MODULES=\(f2fs[[:space:]]*\)/MODULES=(f2fs)/' \
      -e 's/(^HOOKS=\([^)]*)[[:space:]]microcode([[:space:]]|\))/\1\2/' \
      -e 's/[[:space:]]+\)/)/' \
      "$target/etc/mkinitcpio.conf"
  fi

  if [ "$(uname -m)" = "aarch64" ] && [ -x "$target/usr/bin/mkinitcpio" ]; then
    mount --bind /dev "$target/dev"
    mount -t proc proc "$target/proc"
    mount -t sysfs sys "$target/sys"
    chroot "$target" mkinitcpio -P
  else
    printf 'warning: skipped target mkinitcpio regeneration; run it on first boot if F2FS initramfs is missing\n' >&2
  fi
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }
[ "$(id -u)" -eq 0 ] || die "run as root"
[ "$#" -ge 1 ] || { usage >&2; exit 2; }
[ "$#" -le 2 ] || { usage >&2; exit 2; }

device="$1"
rootfs_source="${2:-http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz}"
repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
template_dir="$repo_dir/sdcard/templates"
nodes_source="$repo_dir/mitamae/nodes.yml"
root_f2fs_overprovision_percent=15
root_f2fs_options="rw,noatime,lazytime,nodiscard,background_gc=on,gc_merge,atgc,flush_merge,checkpoint_merge,errors=remount-ro"

[ -f "$repo_dir/mitamae/nodes.local.yml" ] && nodes_source="$repo_dir/mitamae/nodes.local.yml"

[ -b "$device" ] || die "not a block device: $device"
[ -f "$repo_dir/mitamae/roles/default.rb" ] || die "cannot find mitamae role under $repo_dir"
[ -f "$nodes_source" ] || die "cannot find node settings file: $nodes_source"
[ -f "$repo_dir/mitamae/secrets/secrets.yml" ] || die "復号済みの秘密情報がありません: $repo_dir/mitamae/secrets/secrets.yml"
[ -f "$template_dir/rpi3b.sfdisk" ] || die "missing template: $template_dir/rpi3b.sfdisk"
[ -f "$template_dir/fstab.in" ] || die "missing template: $template_dir/fstab.in"
[ -f "$template_dir/mitamae-firstboot" ] || die "missing template: $template_dir/mitamae-firstboot"
[ -f "$template_dir/mitamae-firstboot.service" ] || die "missing template: $template_dir/mitamae-firstboot.service"

need_cmd awk
need_cmd bsdtar
need_cmd curl
need_cmd findmnt
need_cmd install
need_cmd lsblk
need_cmd mkfs.f2fs
need_cmd mkfs.vfat
need_cmd mkimage
need_cmd partprobe
need_cmd rsync
need_cmd sed
need_cmd sfdisk
need_cmd udevadm
need_cmd wipefs

if findmnt -rn -S "$device" >/dev/null 2>&1 ||
   lsblk -nrpo MOUNTPOINT "$device" | awk 'NF { found = 1 } END { exit !found }'; then
  die "$device or its partitions are mounted"
fi

boot_part="$(part_name "$device" 1)"
root_part="$(part_name "$device" 2)"
work_dir="$(mktemp -d)"
boot_mount="$work_dir/boot"
root_mount="$work_dir/root"
rootfs_tar="$work_dir/rootfs.tar.gz"

cleanup() {
  set +e
  mountpoint -q "$root_mount/sys" && umount "$root_mount/sys"
  mountpoint -q "$root_mount/proc" && umount "$root_mount/proc"
  mountpoint -q "$root_mount/dev" && umount "$root_mount/dev"
  mountpoint -q "$boot_mount" && umount "$boot_mount"
  mountpoint -q "$root_mount" && umount "$root_mount"
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

printf 'About to erase %s:\n' "$device"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$device"
printf 'Type YES to continue: '
read -r answer
[ "$answer" = "YES" ] || die "aborted"

wipefs -a "$device"
sfdisk "$device" < "$template_dir/rpi3b.sfdisk"

wait_for_partitions "$device" || die "partitions did not appear"

mkfs.vfat -F 32 -n BOOT "$boot_part"
mkfs.f2fs -f -l ROOT -o "$root_f2fs_overprovision_percent" -O extra_attr,inode_checksum,sb_checksum "$root_part"

mkdir -p "$boot_mount" "$root_mount"
mount "$root_part" "$root_mount"
mkdir -p "$root_mount/boot"
mount "$boot_part" "$boot_mount"

case "$rootfs_source" in
  http://*|https://*)
    printf 'Downloading %s\n' "$rootfs_source"
    curl -fL --retry 3 -o "$rootfs_tar" "$rootfs_source"
    ;;
  *)
    [ -f "$rootfs_source" ] || die "rootfs tarball not found: $rootfs_source"
    rootfs_tar="$rootfs_source"
    ;;
esac

bsdtar -xpf "$rootfs_tar" -C "$root_mount"
mv "$root_mount"/boot/* "$boot_mount"/

boot_partuuid="$(lsblk -no PARTUUID "$boot_part")"
root_partuuid="$(lsblk -no PARTUUID "$root_part")"
[ -n "$boot_partuuid" ] || die "could not read boot PARTUUID"
[ -n "$root_partuuid" ] || die "could not read root PARTUUID"

render_template \
  "$template_dir/fstab.in" \
  "$root_mount/etc/fstab" \
  "$boot_partuuid" \
  "$root_partuuid" \
  "$root_f2fs_options"

configure_target_initramfs "$root_mount"

if [ -f "$boot_mount/boot.txt" ]; then
  sed -i -E \
    -e "s#root=[^[:space:]\"']+#root=PARTUUID=$root_partuuid#g" \
    "$boot_mount/boot.txt"
  if grep -q 'rootfstype=' "$boot_mount/boot.txt"; then
    sed -i -E 's#rootfstype=[^[:space:]"'"'"']+#rootfstype=f2fs#g' "$boot_mount/boot.txt"
  else
    sed -i -E 's#(root=PARTUUID=[^[:space:]"'"'"']+)#\1 rootfstype=f2fs#g' "$boot_mount/boot.txt"
  fi
  if grep -q 'rootflags=' "$boot_mount/boot.txt"; then
    sed -i -E "s#rootflags=[^[:space:]\"']+#rootflags=$root_f2fs_options#g" "$boot_mount/boot.txt"
  else
    sed -i -E "s#(rootfstype=f2fs)#\\1 rootflags=$root_f2fs_options#g" "$boot_mount/boot.txt"
  fi
  (cd "$boot_mount" && mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d boot.txt boot.scr)
fi

mkdir -p "$root_mount/opt/management"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'sdcard/' \
  "$repo_dir/mitamae" "$root_mount/opt/management/"
write_nodes_yml \
  "$nodes_source" \
  "$root_mount/opt/management/mitamae/nodes.yml" \
  "$boot_partuuid" \
  "$root_partuuid"

mkdir -p "$root_mount/usr/local/bin" "$root_mount/usr/local/sbin" "$root_mount/etc/systemd/system"
curl -fL --retry 3 -o "$root_mount/usr/local/bin/mitamae" \
  https://github.com/itamae-kitchen/mitamae/releases/latest/download/mitamae-aarch64-linux
chmod 755 "$root_mount/usr/local/bin/mitamae"

install -m 755 "$template_dir/mitamae-firstboot" "$root_mount/usr/local/sbin/mitamae-firstboot"

install -m 644 "$template_dir/mitamae-firstboot.service" \
  "$root_mount/etc/systemd/system/mitamae-firstboot.service"

mkdir -p "$root_mount/etc/systemd/system/multi-user.target.wants"
ln -sf ../mitamae-firstboot.service \
  "$root_mount/etc/systemd/system/multi-user.target.wants/mitamae-firstboot.service"

sync
printf '\nPrepared %s for Raspberry Pi 3 B Arch Linux ARM aarch64.\n' "$device"
printf 'boot PARTUUID: %s\n' "$boot_partuuid"
printf 'root PARTUUID: %s\n' "$root_partuuid"
printf 'The first boot will run mitamae via mitamae-firstboot.service.\n'
