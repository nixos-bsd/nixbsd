#!/usr/bin/env bash
set -ex

export DESTDIR=${DESTDIR-~/proj/nix/boot}
export NIX_PATH=${NIX_PATH-~/proj/nix}

mkdir -p $DESTDIR/EFI/BOOT
cp $(nix-build '<nixpkgs>' -A pkgsCross.x86_64-freebsd14.freebsd.stand-efi)/bin/boot1.efi $DESTDIR/EFI/BOOT/BOOTX64.EFI
