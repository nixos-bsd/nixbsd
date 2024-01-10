{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.tempfiles;
  mtreeSubmodule = {
    options = {
      file = mkOption {
        type = types.path;
        description = ''
          Directory specification file, in mtree format.
        '';
      };
      root = mkOption {
        type = types.path;
        example = "/var";
        description = ''
          Directory the mtree file should be applied to.
        '';
      };
      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "-d" "-e" "-i" "-U" ];
        description = ''
          Extra flags to pass to {manfile}`mtree(8)`.
        '';
      };
    };
  };
in {
  options = {
    services.tempfiles = {
      package = makePackageOption [ "freebsd" "mtree" ];
      specs = mkOption {
        type = types.listOf (types.submodule mtreeSubmodule);
        description = ''
          Specifications to apply.
        '';
      };
      useDefaultSpecs = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Apply default rules, which populate var.
          Some services may fail if this is not set or replicated.
        '';
      };
    };
  };

  config = {
    rc.services.tempfiles = {
      description = "Setup tempfiles from specifications";
      provides = "tempfiles";
      commands.start = concatMapStringsSep "\n" (spec:
        escapeShellArgs [
          "${cfg.package}/bin/mtree"
          "-f"
          spec.file
          "-p"
          spec.root
        ] ++ spec.extraFlags) cfg.specs;
    };

    services.tempfiles.specs = mkIf cfg.useDefaultSpecs [{
      file = ./BSD.var.dist;
      root = "/var";
      extraFlags = [ "-d" "-e" "-i" "-U" ];
    }];
  };
}

