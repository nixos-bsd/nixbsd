{ lib, ... }:
with lib;
{
  options = {
    boot.loader.espDerivation = mkOption {
      type = types.nullOr types.pathInStore;
      description = ''
        The derivation to build in order to populate the EFI system partiion
      '';
      default = null;
    };
    boot.loader.bootDerivation = mkOption {
      type = types.nullOr types.pathInStore;
      description = ''
        The derivation to build in order to populate the /boot folder on the root filesystem
      '';
      default = null;
    };
  };
}
