boot_partuuid = node[:boot_partuuid] || '0b446079-01'
root_partuuid = node[:root_partuuid] || '0b446079-02'
root_f2fs_options = 'rw,noatime,lazytime,nodiscard,background_gc=on,gc_merge,atgc,flush_merge,checkpoint_merge,errors=remount-ro'
base_packages = %w[
  sudo
  openssh
  f2fs-tools
  dosfstools
  uboot-tools
  rsync
  git
  nodejs
  npm
  go
  tmux
  bubblewrap
  dool
  lsof
  sysstat
]

execute 'initialize pacman keyring' do
  command 'pacman-key --init'
  not_if 'test -s /etc/pacman.d/gnupg/pubring.gpg'
end

execute 'populate Arch Linux ARM keyring' do
  command 'pacman-key --populate archlinuxarm'
  not_if 'pacman-key --list-keys 68B3537F39A313B3E574D06777193F152BDBE6A6 >/dev/null 2>&1'
end

base_packages.each do |package_name|
  package package_name do
    action :install
  end
end

execute 'lock root password login' do
  command 'passwd -l root'
  not_if "passwd -S root | awk '{ exit ($2 == \"L\" || $2 == \"LK\") ? 0 : 1 }'"
end

execute 'lock alarm password login' do
  command 'passwd -l alarm'
  only_if 'id -u alarm >/dev/null 2>&1'
  not_if "passwd -S alarm | awk '{ exit ($2 == \"L\" || $2 == \"LK\") ? 0 : 1 }'"
end

execute 'disable alarm shell' do
  command 'usermod -s /usr/bin/nologin alarm'
  only_if 'id -u alarm >/dev/null 2>&1'
  not_if "test \"$(getent passwd alarm | cut -d: -f7)\" = '/usr/bin/nologin'"
end

execute 'remove alarm from wheel' do
  command 'gpasswd -d alarm wheel'
  only_if 'id -nG alarm 2>/dev/null | grep -qw wheel'
end

execute 'enable f2fs in mkinitcpio modules' do
  command "sed -i -E 's/^MODULES=\\(([^)]*)\\)/MODULES=(f2fs \\1)/; s/^MODULES=\\(f2fs[[:space:]]*\\)/MODULES=(f2fs)/' /etc/mkinitcpio.conf"
  not_if "grep -Eq '^MODULES=\\([^)]*\\bf2fs\\b[^)]*\\)' /etc/mkinitcpio.conf"
end

execute 'remove unsupported microcode hook from mkinitcpio' do
  command "sed -i -E 's/(^HOOKS=\\([^)]*)[[:space:]]microcode([[:space:]]|\\))/\\1\\2/; s/[[:space:]]+\\)/)/' /etc/mkinitcpio.conf"
  only_if "grep -Eq '^HOOKS=.*\\bmicrocode\\b' /etc/mkinitcpio.conf"
end

file '/etc/fstab' do
  owner 'root'
  group 'root'
  mode '644'
  content "PARTUUID=#{boot_partuuid}  /boot  vfat  rw,noatime,fmask=0022,dmask=0022  0  0\n" \
          "PARTUUID=#{root_partuuid}  /      f2fs  #{root_f2fs_options}  0  0\n"
end

execute 'configure f2fs root boot flags' do
  command "sed -i -E 's# rootflags=[^[:space:]\"'\"'\"']+##g; s#(rootfstype=f2fs)#\\1 rootflags=#{root_f2fs_options}#g' /boot/boot.txt"
  only_if "test -f /boot/boot.txt && grep -q 'rootfstype=f2fs' /boot/boot.txt && ! grep -q 'rootflags=#{root_f2fs_options}' /boot/boot.txt"
  notifies :run, 'execute[regenerate u-boot boot script]', :immediately
end

execute 'regenerate u-boot boot script' do
  command 'cd /boot && mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d boot.txt boot.scr'
  action :nothing
end

directory '/etc/ssh/sshd_config.d' do
  owner 'root'
  group 'root'
  mode '755'
end

file '/etc/ssh/sshd_config.d/10-hardening.conf' do
  owner 'root'
  group 'root'
  mode '644'
  content "PermitRootLogin no\n" \
          "PasswordAuthentication no\n" \
          "KbdInteractiveAuthentication no\n" \
          "PubkeyAuthentication yes\n"
  notifies :run, 'execute[validate sshd config]', :immediately
  notifies :run, 'execute[reload sshd]'
end

execute 'validate sshd config' do
  command 'sshd -t'
  action :nothing
end

service 'sshd' do
  action [:enable, :start]
end

execute 'reload sshd' do
  command 'systemctl reload sshd'
  action :nothing
end
