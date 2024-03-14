{ config, lib, pkgs, ... }:

let
  cfg = config.services.seatd;
  inherit (lib) mkEnableOption mkOption mdDoc types;
in
{
  meta.maintainers = with lib.maintainers; [ sinanmohd ];

  options.services.seatd = {
    enable = mkEnableOption (mdDoc "seatd");

    user = mkOption {
      type = types.str;
      default = "root";
      description = mdDoc "User to own the seatd socket";
    };
    group = mkOption {
      type = types.str;
      default = "seat";
      description = mdDoc "Group to own the seatd socket";
    };
    logLevel = mkOption {
      type = types.enum [ "debug" "info" "error" "silent" ];
      default = "info";
      description = mdDoc "Logging verbosity";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ seatd sdnotify-wrapper ];
    users.groups.seat = lib.mkIf (cfg.group == "seat") {};

    rc.services.seatd = rec {
      provides = "seatd";
      requires = [ "DAEMON" ];
      description = "Seat management daemon";

      hasPidfile = true;
      command = "${pkgs.freebsd.daemon}/bin/daemon";
      procname = "${pkgs.seatd.bin}/bin/seatd";
      commandArgs =
        [ "-s" "err" "-T" "seatd" "-p" "/var/run/seatd.pid" procname "-g" "video"];
    };
  };
}
