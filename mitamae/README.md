# mitamae 構成管理

このディレクトリは Raspberry Pi 上で実行する mitamae の構成です。

- `roles/default.rb`: 適用するロールの入口です。
- `cookbooks/`: base 設定と WLAN 設定のレシピです。
- `nodes.yml`: admin ユーザ、一般ユーザ、PARTUUID などのサンプル設定です。
- `files/authorized_keys`: admin ユーザに配置する SSH 公開鍵のサンプルです。
- `run.sh`: Raspberry Pi 上で現在の構成を再適用します。
- `bootstrap.sh`: Raspberry Pi に mitamae バイナリを入れるための補助スクリプトです。

## 秘密情報

`secrets/secrets.yml` と `encrypted/secrets.yml` にはサンプル値が入っています。
実運用では自分用の値に置き換えてください。

```yaml
wlan:
  ssid: ExampleWiFi
  passphrase: example-passphrase

password_hashes:
  admin: '$y$j9T$replace-this-with-a-real-password-hash'
```

復号済みの値を編集します。

```sh
$EDITOR secrets/secrets.yml
```

必要なら自分用の SOPS 設定を作って暗号化ファイルを生成します。

```sh
cp ../.sops.yaml ../.sops.local.yaml
sops --config ../.sops.local.yaml --encrypt secrets/secrets.yml > encrypted/secrets.yml
```

通常設定の `nodes.yml` と復号済みの秘密情報を両方渡して mitamae を実行します。

```sh
sudo mitamae local --node-yaml=nodes.yml --node-yaml=secrets/secrets.yml roles/default.rb
```

`run.sh` も同じコマンドを実行します。`secrets/secrets.yml` が無い場合は
エラーで停止します。公開リポジトリに含まれる `encrypted/secrets.yml` は
公開可能なサンプルです。

## 暗号化ファイルの更新

`secrets/secrets.yml` を編集し、自分用の `.sops.local.yaml` を使って暗号化します。

```sh
sops --config ../.sops.local.yaml --encrypt secrets/secrets.yml > encrypted/secrets.yml
```

実行サーバに `sops` や `age` は不要です。手元 PC で復号してから、復号済みの
`secrets/secrets.yml` を mitamae ツリーと一緒に実行サーバへ転送してください。
