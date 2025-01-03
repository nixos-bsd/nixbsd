{ lib, pkgs, config, ... }:
with lib;
let cfg = config.programs.su;
in {
  options = {
    programs.su = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the `su` command.
        '';
      };

      package = mkPackageOption pkgs [ "openbsd" "su" ] { };
    };
  };

  config = mkIf cfg.enable {
    security.wrappers.su = {
      setuid = true;
      owner = "root";
      group = "root";
      permissions = "+rx";
      source = lib.getExe cfg.package;
    };
  };
}
