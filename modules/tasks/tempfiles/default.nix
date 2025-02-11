{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.tempfiles;
  mtreeSubmodule = { config, ... }: {
    options = {
      file = mkOption {
        type = types.path;
        description = ''
          Directory specification file, in mtree format.
        '';
      };
      text = mkOption {
        type = types.nullOr types.lines;
        description = ''
          Raw text of the mtree file.
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
          Extra flags to pass to {manpage}`mtree(8)`.
        '';
      };
    };
    config = {
      file = mkIf (config.text != null)
        (pkgs.writeText "tempfile-mtree.cfg" config.text);
    };
  };
in {
  options = {
    services.tempfiles = {
      package = mkOption {
        type = types.package;
        default = {
          freebsd = pkgs.freebsd.mtree;
          openbsd = pkgs.openbsd.mtree;
        }.${pkgs.stdenv.hostPlatform.parsed.kernel.name};
        description = ''
          `mtree` package to use when setting up tempfiles.
        '';
      };
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
    init.services.tempfiles = {
      description = "Setup tempfiles from specifications";
      dependencies = [ "mountcritlocal" ];
      before = [ "FILESYSTEMS" ];
      startType = "oneshot";
      startCommand = [(pkgs.writeScript "tempfiles-start"
        (''
          #!${pkgs.runtimeShell}
        '' +
        (concatMapStringsSep "\n" (spec:
          escapeShellArgs
          ([ "${cfg.package}/bin/mtree" "-f" spec.file "-p" spec.root ]
            ++ spec.extraFlags)) cfg.specs)))];
    };

    services.tempfiles.specs = mkIf cfg.useDefaultSpecs [{
      text = readFile ./BSD.var.dist;
      root = "/var";
      extraFlags = [ "-d" "-e" "-i" "-U" ];
    }];
  };
}

