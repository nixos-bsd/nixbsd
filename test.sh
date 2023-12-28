#!/usr/bin/env bash

export NIX_PATH=${NIX_PATH-~/proj/nix}
TMP_FILE=$(mktemp)
nix-build '<nixbsd>' -A config.system.build.vmImage --no-out-link >$TMP_FILE && \
	read BASE_IMAGE <$TMP_FILE && \
	qemu-img create -f qcow2 -b $BASE_IMAGE -F qcow2 $TMP_FILE && \
	qemu-system-x86_64 -drive file=$TMP_FILE,format=qcow2 -bios ${OVMF_BIOS-/usr/share/ovmf/OVMF.fd} -m ${QEMU_MEM-1024}

rm -f $TMP_FILE
