{ config, lib, ... }: {
  imports = [ ../base/default.nix ];

  nixpkgs.overlays = [
    (import ../../overlays/freebsd-main.nix)
  ];

  virtualisation.vmVariant.virtualisation.diskImage = lib.mkOverride 10 null;
  virtualisation.vmVariant.virtualisation.netMountNixStore = true;
  virtualisation.vmVariant.virtualisation.netMountBoot = true;
  readOnlyNixStore.writableLayer = "/nix/.rw-store";
}
