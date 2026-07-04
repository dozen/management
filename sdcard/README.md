# Raspberry Pi 3 B 用 Arch Linux ARM イメージ

このディレクトリは、Raspberry Pi 3 B 用の microSD カードを作成します。

作成される構成:

- Arch Linux ARM aarch64 rootfs
- 2 GiB の FAT32 パーティション `/boot`
- 残り領域を使う F2FS の `/`
- F2FS の 15% overprovisioning
- F2FS の `extra_attr`, `inode_checksum`, `sb_checksum`
- `/usr/local/bin/mitamae`
- 初回起動時に `/opt/management/mitamae/roles/default.rb` を実行する
  `mitamae-firstboot.service`

`templates/` には、パーティション定義、`fstab`、初回起動スクリプト、systemd
unit を置いています。`prepare-rpi3b-arch64.sh` はこれらを使って対象 rootfs に
設定ファイルを配置します。

対象の microSD カードを Linux ホストに挿入してから実行します。

```sh
sudo sdcard/prepare-rpi3b-arch64.sh /dev/sdX
```

## 実行前チェックリスト

- `lsblk` で対象デバイスが `/dev/sdX` または `/dev/mmcblkN` のどれか確認する。
- 対象デバイスとそのパーティションがマウントされていないことを確認する。
- `mitamae/nodes.local.yml` を使う場合は先に作成しておく。
- `mitamae/secrets/secrets.yml` を復号済みにしておく。
- rootfs tarball をローカル指定する場合は、パスが正しいことを確認する。
- 確認プロンプトで `YES` と入力すると、指定デバイスは破壊的に初期化される。

ホスト側には `bsdtar`, `curl`, `dosfstools` (`mkfs.vfat`),
`f2fs-tools` (`mkfs.f2fs`), `rsync`, `sfdisk`, `uboot-tools` (`mkimage`) が
必要です。

ローカルの rootfs tarball を指定することもできます。

```sh
sudo sdcard/prepare-rpi3b-arch64.sh /dev/sdX ./ArchLinuxARM-rpi-aarch64-latest.tar.gz
```

このスクリプトは指定したデバイスを破壊的に初期化します。パーティション作成
前に `YES` の入力を求めます。

処理内容:

- カードを書き込み、現在の `mitamae/` ツリーを埋め込む
- `mitamae/nodes.local.yml` があればそれを優先し、なければ `mitamae/nodes.yml` を使う
- boot loader の root PARTUUID と F2FS `rootflags` を更新する
- 初回起動時の `/etc/fstab` が正しくなるよう、対応する PARTUUID を
  `mitamae/nodes.yml` に書き込む

WLAN の認証情報とパスワードハッシュは、実行前に
`mitamae/secrets/secrets.yml` として復号しておく必要があります。実行サーバ上では
復号しません。

デフォルトの rootfs URL:

```text
http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz
```
