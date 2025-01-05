{ lib, ... }:
with lib;
{
  options = {
    boot.loader.espContents = mkOption {
      type = types.nullOr types.pathInStore;
      description = ''
        The derivation to build in order to populate the EFI system partiion
      '';
      default = null;
    };
    boot.loader.bootContents = mkOption {
      type = types.nullOr types.pathInStore;
      description = ''
        The derivation to build in order to populate the /boot folder on the root filesystem
      '';
      default = null;
    };
  };
}
