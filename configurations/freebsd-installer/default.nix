{
  config,
  lib,
  ...
}:
{
  imports = [
    ../extra/default.nix

    ../../modules/installer/iso-image.nix
  ];

  nixpkgs.hostPlatform = "x86_64-freebsd";
  nixpkgs.buildPlatform = "x86_64-linux";


  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-cdrom ${config.system.build.isoImage}"
    "-boot c" # not working - sadly
  ];

  # virtualisation.vmVariant.virtualisation.graphics = lib.mkOverride 10 false;
  virtualisation.vmVariant.virtualisation.diskImage = lib.mkOverride 10 null;
  virtualisation.vmVariant.virtualisation.netMountNixStore = lib.mkForce false;
  virtualisation.vmVariant.virtualisation.netMountBoot = lib.mkForce false;
}
