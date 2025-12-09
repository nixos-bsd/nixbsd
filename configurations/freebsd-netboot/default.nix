{ config, lib, ... }: {
  imports = [ ../extra/default.nix ];

  virtualisation.vmVariant.virtualisation.diskImage = lib.mkOverride 10 null;
  virtualisation.vmVariant.virtualisation.netMountNixStore = true;
  virtualisation.vmVariant.virtualisation.netMountBoot = true;
  readOnlyNixStore.writableLayer = "/nix/.rw-store";
}
