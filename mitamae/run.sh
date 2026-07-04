#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

nodes_file='nodes.yml'
[ -f nodes.local.yml ] && nodes_file='nodes.local.yml'

if [ ! -f secrets/secrets.yml ]; then
  printf 'エラー: 復号済みの秘密情報がありません: secrets/secrets.yml\n' >&2
  printf '復号コマンド: sops --decrypt encrypted/secrets.yml > secrets/secrets.yml\n' >&2
  exit 1
fi

sudo mitamae local \
  --node-yaml="$nodes_file" \
  --node-yaml=secrets/secrets.yml \
  roles/default.rb
