{ config, lib, pkgs, ... }:
with lib;
let
in {
  options = {
    boot.initmd.contents = mkOption {
      type = types.listOf types.path;
      description = ''
        Paths to include in the initmd image.
      '';
      default = [];
    };
    boot.initmd.image = mkOption {
      type = types.path;
      description = ''
        The initmd image.
      '';
    };
  };
  config = {
    boot.initmd.image = import ../../../lib/make-partition-image.nix {
      inherit pkgs lib;
      label = "initmd";
      filesystem = "ufs";
      nixStorePath = "/nix/store";
      nixStoreClosure = config.boot.initmd.contents;
      makeRootDirs = true;
    };
  };
}
