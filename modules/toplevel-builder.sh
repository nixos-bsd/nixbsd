#!/usr/bin/env bash

mkdir -p $out/boot
cp -r $kernel/kernel $out/boot/kernel
for bootFile in $bootFiles; do
	cp -r $bootLoader/$bootFile $out/boot
done
mkdir -p $out/boot/loader.conf.d
echo "init_path=\"$init\"" >$out/boot/loader.conf.d/$label.conf
echo "init_shell=\"$initShell\"" >>$out/boot/loader.conf.d/$label.conf
echo "vfs.root.mountfrom=\"ufs:/dev/ada1p1\"" >>$out/boot/loader.conf.d/$label.conf
