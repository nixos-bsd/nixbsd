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
        cp ${pkgs.freebsd.stand-efi}/bin/loader.efi boot/efi/boot/bootx64.efi
        cp -r ${pkgs.freebsd.stand-efi}/bin/{lua,defaults} boot/boot
        makefs -t msdos -o fat_type=32 -o volume_label=EFI -M 32M boot boot.img

        # UFS root partition
        mkdir -p root/dev

        export NIX_STATE_DIR=$TMPDIR/state
        nix-store --load-db < ${closureInfo}/registration
        nix copy --no-check-sigs --to root ${config.system.build.toplevel}

        makefs -o version=2 -o label=root -b 10% root root.img

        mkimg -o $out -s gpt -p efi:=boot.img -p freebsd-ufs:=root.img 
    '';
  };
}
