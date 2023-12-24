#!/usr/bin/env bash
set -ex

NIX_PATH=${NIX_PATH-~/proj/nix}
DESTDIR=${DESTDIR-~/proj/nix/main}
DESTFILE=${DESTFILE-~/proj/nix/disk.img}
PROFILE="$(nix-build '<nixbsd>' -A config.toplevel --no-out-link)"
MAKEFS="$(nix-build '<nixpkgs>' -A freebsd.packages14.makefs --option substitute false)/bin/makefs"
MKIMG="$(nix-build '<nixpkgs>' -A freebsd.packages14.mkimg --option substitute false)/bini/mkimg"
TMPPART="$(mktemp)"

nix copy --no-check-sigs --to $DEST $PROFILE
sudo rm -rf $DEST/boot
cp -r $PROFILE/boot $DEST/boot
mkdir -p $DEST/dev
$MAKEFS -o version=2 -o label=main $TMPPART $DEST
$MKIMG -o $DESTFILE -s gpt -p freebsd-ufs/main:=$TMPPART
rm -f $TMPPART
