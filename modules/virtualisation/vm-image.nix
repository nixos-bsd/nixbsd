# NixOS makes a fancy VM image, but that's not possible without a real bootloader install script.
# For now just make a VM image for testing with minimal configurability
# TODO: use the real NixOS VM image package, with some changes to work on FreeBSD

{ pkgs, config, lib, ... }:
{
  # No options, config.system.build lets us set whatever we want
  config = {
    system.build.vmImage = let
      closureInfo = pkgs.buildPackages.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
      binPath = with pkgs.buildPackages; lib.makeBinPath ( stdenv.initialPath ++ [
        freebsd.packages14.makefs
        freebsd.packages14.mkimg
        nix
      ]);
    in
    pkgs.buildPackages.runCommand "freebsd-image.qcow2" { } ''
        export PATH="${binPath}"

        # EFI boot partition
        mkdir -p boot/efi/boot boot/boot
        cp ${pkgs.freebsd.stand-efi}/bin/boot1.efi boot/efi/boot/bootx64.efi
        touch $TMPDIR/boot.img
        makefs -t msdos -o fat_type=16 -o volume_label=EFI -o create_size=32m $TMPDIR/boot.img boot

        # UFS root partition
        mkdir -p root/dev root/boot/available-systems root/boot/loader.conf.d root/etc root/run
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

        makefs -o version=2 -o label=root -b 10% $TMPDIR/root.img root

        mkimg -o $out -s gpt -f qcow2 -p efi:=$TMPDIR/boot.img -p freebsd-ufs:=$TMPDIR/root.img 
    '';
  };
}
