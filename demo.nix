{
  runCommand,
  writeScript,
  openbsd,
  freebsd,
  qemu,
  OVMF,
  pkgsCross,
  runtimeShell,
}:
let
  crossSystem = pkgsCross.x86_64-openbsd;
  runscript = writeScript "run.sh" ''
    #!${runtimeShell}

    NIX_DISK_IMAGE="$(readlink -f nixbsd-openbsd.qcow2)"
    if ! test -e "$NIX_DISK_IMAGE" || ! ${qemu}/bin/qemu-img info "$NIX_DISK_IMAGE" | grep ${diskimage} &>/dev/null; then
      echo "Virtualisation disk image doesn't exist or needs rebase, creating..."
      rm -f "$NIX_DISK_IMAGE"
      ${qemu}/bin/qemu-img create \
        -f qcow2 \
        -b ${diskimage} \
        -F qcow2 \
        "$NIX_DISK_IMAGE"
    fi

    NIX_EFI_VARS=$(readlink -f "''${NIX_EFI_VARS:-nixbsd-efi-vars.fd}")
    # VM needs writable EFI vars
    if ! test -e "$NIX_EFI_VARS"; then
      cp ${OVMF.fd.variables} "$NIX_EFI_VARS"
      chmod 0644 "$NIX_EFI_VARS"
    fi

    exec ${qemu}/bin/qemu-kvm -machine type=q35,accel=kvm:tcg -cpu max \
        -name nixbsd-openbsd \
        -m 4096 \
        -smp 4 \
        -device virtio-rng-pci \
        -net nic,netdev=user.0,model=virtio \
        -netdev user,id=user.0,"$QEMU_NET_OPTS" \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=${OVMF.firmware} \
        -drive if=pflash,format=raw,unit=1,readonly=off,file=$NIX_EFI_VARS \
        -drive index=0,id=drive0,if=none,file="$NIX_DISK_IMAGE" -device virtio-blk-pci,drive=drive0 \
        $QEMU_OPTS \
        "$@"
  '';
  diskimage =
    runCommand "openbsd.qcow2"
      {
        nativeBuildInputs = [
          freebsd.mkimg
          openbsd.makefs
        ];
      }
      ''
        mkdir -p $TMP/efi_part/efi/boot $TMP/ufs_part
        cp -r ${crossSystem.openbsd.sys}/* $TMP/ufs_part
        cp ${crossSystem.openbsd.stand}/bin/BOOTX64.EFI $TMP/efi_part/efi/boot/BOOTX64.EFI
        makefs -M 100M -t ffs $TMP/ufs_part.img $TMP/ufs_part
        makefs -M 20M -t msdos $TMP/efi_part.img $TMP/efi_part

        EFI_BYTES=$(wc -c $TMP/efi_part.img | cut -d' ' -f1)
        OFFSET_SECTORS=$(($EFI_BYTES / 512 + 34))  # magic number?

        mkimg -v -y -o $TMP/bsd.img -s bsd -S 512 -H 255 -T 63 -b ${crossSystem.openbsd.stand}/bin/mbr -f raw -r $OFFSET_SECTORS -p freebsd-ufs:=$TMP/ufs_part.img -p-
        mkimg -y -o $out -s gpt -S 512 -H 255 -T 63 -P 512 -f qcow2 -p efi/ESP:=$TMP/efi_part.img -p openbsd-data/data:=$TMP/bsd.img
      '';
in
runCommand "nixbsd-openbsd"
  {
    meta.mainProgram = "run.sh";
  }
  ''
    mkdir -p $out/bin
    ln -s ${diskimage} $out/disk.qcow2
    ln -s ${runscript} $out/bin/run.sh
  ''
