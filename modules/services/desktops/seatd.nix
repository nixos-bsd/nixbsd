{ config, lib, pkgs, ... }:

let
  cfg = config.services.seatd;
  inherit (lib) mkEnableOption mkOption types;
in
{
  meta.maintainers = with lib.maintainers; [ sinanmohd ];

  options.services.seatd = {
    enable = mkEnableOption ("seatd");

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to own the seatd socket";
    };
    group = mkOption {
      type = types.str;
      default = "seat";
      description = "Group to own the seatd socket";
    };
    logLevel = mkOption {
      type = types.enum [ "debug" "info" "error" "silent" ];
      default = "info";
      description = "Logging verbosity";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ seatd ];
    users.groups.seat = lib.mkIf (cfg.group == "seat") {};

    init.services.seatd = {
      description = "Seat management daemon";
      dependencies = [ "DAEMON" ];

      startType = "foreground";
      startCommand = [ "${pkgs.seatd.bin}/bin/seatd" "-u" cfg.user "-g" cfg.group ];
    };
  };
}
