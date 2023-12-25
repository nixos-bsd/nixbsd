#!/usr/bin/env bash
set -ex

export NIX_PATH=${NIX_PATH-~/proj/nix}
export DESTDIR=${DESTDIR-~/proj/nix/main}
export DESTFILE=${DESTFILE-~/proj/nix/disk.img}
export PROFILE="$(nix-build '<nixbsd>' -A config.system.toplevel --no-out-link)"
export MAKEFS="$(nix-build '<nixpkgs>' -A freebsd.packages14.makefs --option substitute false)/bin/makefs"
export MKIMG="$(nix-build '<nixpkgs>' -A freebsd.packages14.mkimg --option substitute false)/bin/mkimg"
export TMPPART="$(mktemp)"

sudo rm -rf $DESTDIR; mkdir -p $DESTDIR
nix copy --no-check-sigs --to $DESTDIR $PROFILE
cp -r $PROFILE/boot $DESTDIR/boot
mkdir -p $DESTDIR/dev
$MAKEFS -o version=2 -o label=main $TMPPART $DESTDIR
$MKIMG -o $DESTFILE -s gpt -p freebsd-ufs/main:=$TMPPART
rm -f $TMPPART
