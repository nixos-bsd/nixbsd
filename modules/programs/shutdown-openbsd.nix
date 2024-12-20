{ lib, pkgs, config, ... }:
with lib;
let cfg = config.programs.shutdown;
in {
  options = {
    programs.shutdown = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the `shutdown` command.
          These are generally setuid so that members of a certain group can run them.
          This is unrelated to `reboot` and `halt`, among others
        '';
      };

      group = mkOption {
        type = types.str;
        default = "wheel";
        description = ''
          Group which can run the `shutdown` and `poweroff` commands.
        '';
      };

      package = mkPackageOption pkgs [ "openbsd" "shutdown" ] { };
    };
  };

  config = mkIf cfg.enable {
    security.wrappers.shutdown = {
      setuid = true;
      owner = "root";
      inherit (cfg) group;
      permissions = "u+rx,g+rx";
      source = "${cfg.package}/bin/shutdown";
    };
  };
}
