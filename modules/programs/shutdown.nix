{ lib, pkgs, config, ... }:
with lib;
let cfg = config.programs.shutdown;
in {
  options = {
    programs.shutdown = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Whether to enable the `shutdown` and `poweroff` commands.
          These are generally setuid so that members of a certain group can run them.
          This is unrelated to `reboot` and `halt`, among others
        '';
      };

      group = mkOption {
        type = types.str;
        default = "wheel";
        description = lib.mdDoc ''
          Group which can run the `shutdown` and `poweroff` commands.
        '';
      };

      package = mkPackageOption pkgs [ "freebsd" "shutdown" ] { };
    };
  };

  config = mkIf cfg.enable {
    security.wrappers.shutdown = {
      setuid = true;
      owner = "root";
      inherit (cfg) group;
      permissions = "u+rx,g+rx,o+r";
      source = "${pkgs.freebsd.shutdown}/bin/shutdown";
    };

    security.wrappers.poweroff = {
      setuid = true;
      owner = "root";
      inherit (cfg) group;
      permissions = "u+rx,g+rx,o+r";
      source = "${pkgs.freebsd.shutdown}/bin/poweroff";
    };
  };
}
