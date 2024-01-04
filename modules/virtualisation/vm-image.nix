# NixOS makes a fancy VM image, but that's not possible without a real bootloader install script.
# For now just make a VM image for testing with minimal configurability
# TODO: use the real NixOS VM image package, with some changes to work on FreeBSD

{ pkgs, config, lib, ... }: {
  # No options, config.system.build lets us set whatever we want
  config = {
    system.build.vmImage = let
      closureInfo = pkgs.buildPackages.closureInfo {
        rootPaths = [ config.system.build.toplevel ];
      };
      binPath = with pkgs.buildPackages;
        lib.makeBinPath (stdenv.initialPath ++ [
          freebsd.packages14.makefs
          freebsd.packages14.mkimg
          freebsd.packages14.mtree
          nix
        ]);
    in pkgs.buildPackages.runCommand "freebsd-image.qcow2" { } ''
      export PATH="${binPath}"

      # EFI boot partition
      mkdir -p boot/efi/boot boot/boot
      cp ${pkgs.freebsd.stand-efi}/bin/boot1.efi boot/efi/boot/bootx64.efi
      touch $TMPDIR/boot.img
      makefs -t msdos -o fat_type=16 -o volume_label=EFI -o create_size=32m $TMPDIR/boot.img boot

      # UFS root partition
      mkdir -p root/dev root/boot/available-systems root/boot/loader.conf.d root/etc
      cp -r ${pkgs.freebsd.stand-efi}/bin/{lua,defaults} root/boot
      cp ${pkgs.freebsd.stand-efi}/bin/loader.efi root/boot
      ln -s ${config.system.build.toplevel} root/boot/available-systems/builtin

      chmod +w root/boot/lua
      mv root/boot/lua/loader.lua root/boot/lua/loader_orig.lua
      cp -r ${../system/boot/nixbsd-loader.lua} root/boot/lua/loader.lua
      chmod -w root/boot/lua

      export NIX_STATE_DIR=$TMPDIR/state
      nix-store --load-db < ${closureInfo}/registration
      nix --extra-experimental-features nix-command copy --no-check-sigs --to ./root ${config.system.build.toplevel}

      cd root
      echo '/set type=file uid=0 gid=0' >>.mtree
      echo '/set type=dir uid=0 gid=0' >>.mtree
      echo '/set type=link uid=0 gid=0' >>.mtree
      echo
      find . -type d | awk '{ print $0, "type=dir" }' >>.mtree
      find . -type f | awk '{ print $0, "type=file" }' >>.mtree
      find . -type l | awk '{ print $0, "type=link" }' >>.mtree
      makefs -o version=2 -o label=root -b 10% -F .mtree $TMPDIR/root.img .

      mkimg -o $out -s gpt -f qcow2 -p efi:=$TMPDIR/boot.img -p freebsd-ufs:=$TMPDIR/root.img
    '';

    system.build.vmImageRunner = let
      startVM = ''
        #! ${pkgs.buildPackages.runtimeShell}
        set -e

        # Create a directory for storing temporary data of the running VM.
        if [ -z "$TMPDIR" ] || [ -z "$USE_TMPDIR" ]; then
            TMPDIR=$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)
        fi

        NIX_DISK_IMAGE=$(readlink -f "''${NIX_DISK_IMAGE:-$TMPDIR/nixbsd.qcow2}") || test -z "$NIX_DISK_IMAGE"

        if test -n "$NIX_DISK_IMAGE" && ! test -e "$NIX_DISK_IMAGE"; then
          echo "Disk image do not exist, creating the virtualisation disk image..."
          # Create a writable qcow2 image using the systemImage as a backing
          # image.

          # CoW prevent size to be attributed to an image.
          # FIXME: raise this issue to upstream.
          ${pkgs.pkgsBuildBuild.qemu}/bin/qemu-img create \
            -f qcow2 \
            -b ${config.system.build.vmImage} \
            -F qcow2 \
            "$NIX_DISK_IMAGE"
          echo "Virtualisation disk image created."
        fi

        NIX_EFI_VARS=$(readlink -f "''${NIX_EFI_VARS:-$TMPDIR/efi-vars.fd}")
        # VM needs writable EFI vars
        if ! test -e "$NIX_EFI_VARS"; then
          cp ${pkgs.pkgsBuildBuild.OVMF.fd.variables} "$NIX_EFI_VARS"
          chmod 0644 "$NIX_EFI_VARS"
        fi

        exec ${pkgs.pkgsBuildBuild.qemu}/bin/qemu-kvm \
          -name nixbsd \
          -m 1024 \
          -smp 2 \
          -device virtio-rng-pci \
          -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.pkgsBuildBuild.OVMF.fd.firmware} \
          -drive if=pflash,format=raw,unit=1,readonly=off,file=$NIX_EFI_VARS \
          -drive format=qcow2,media=disk,readonly=off,file=$NIX_DISK_IMAGE \
          $QEMU_OPTS \
          "$@"
      '';
    in pkgs.runCommand "freebsd-vm" {
      preferlocalBuild = true;
      meta.mainProgram = "run-nixbsd-vm";
    } ''
      mkdir -p $out/bin
      ln -s ${config.system.build.toplevel} $out/system
      ln -s ${
        pkgs.buildPackages.writeScript "run-nixbsd-vm" startVM
      } $out/bin/run-nixbsd-vm
    '';
  };
}
