# rpi3-arch-config-management-sample

Raspberry Pi 3 B 用の Arch Linux ARM イメージ作成と、初回起動後の構成管理を
まとめる公開向けテンプレートです。

## ディレクトリ構成

- `sdcard/`: Raspberry Pi 3 B 用の microSD カードを作成します。
- `mitamae/`: Raspberry Pi 上で実行する mitamae のレシピと設定です。

## 通常の流れ

1. 必要に応じてサンプル設定を置き換えます。

   ```sh
   cp .sops.yaml .sops.local.yaml
   cp mitamae/nodes.yml mitamae/nodes.local.yml
   cp mitamae/files/authorized_keys mitamae/files/authorized_keys.local
   ```

   `authorized_keys.local` には自分の SSH 公開鍵を入れてください。

2. 必要に応じて秘密情報を編集し、SOPS で暗号化されたファイルを作成します。

   ```sh
   $EDITOR mitamae/secrets/secrets.yml
   sops --config .sops.local.yaml --encrypt mitamae/secrets/secrets.yml > mitamae/encrypted/secrets.yml
   ```

3. Linux ホストに対象の microSD カードを挿入し、デバイス名を確認します。

   ```sh
   lsblk
   ```

4. microSD カードを作成します。

   ```sh
   sudo sdcard/prepare-rpi3b-arch64.sh /dev/sdX
   ```

   このコマンドは指定したデバイスを破壊的に初期化します。必ず対象デバイスを
   確認してから実行してください。

5. Raspberry Pi を初回起動します。イメージに埋め込まれた
   `mitamae-firstboot.service` が `/opt/management/mitamae/roles/default.rb` を
   一度だけ実行します。

6. 以後、構成を再適用する場合は Raspberry Pi 上で実行します。

   ```sh
   cd mitamae
   ./run.sh
   ```
