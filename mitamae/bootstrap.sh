#!/bin/sh
set -eu

curl -L -o /usr/local/bin/mitamae \
  https://github.com/itamae-kitchen/mitamae/releases/latest/download/mitamae-aarch64-linux
chmod 755 /usr/local/bin/mitamae
/usr/local/bin/mitamae version
