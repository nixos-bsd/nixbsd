{ pkgs, lib, ... }:
with lib;
{
  options = {
    boot.loader.espDerivation = mkOption {
      type = types.pathInStore;
      description = ''
        The derivation to build in order to populate the EFI system partiion
      '';
    };
  };
}
