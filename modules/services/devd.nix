{ config, lib, utils, pkgs, ... }:

with lib;

let

  cfg = config.services.devd;

in {
  options.services.devd = {
    enable = mkEnableOption "devd service";
  };

  config.rc.services.devd = mkIf cfg.enable {
    provides = "devd";
    description = "Device Daemon";
    command = "${pkgs.freebsd.devd}/bin/devd";

    precmds.start = ''
      if ! checkyesno devd_enable; then
        sysctl hw.bus.devctl_queue=0
      fi
    '';
  };
  config.environment.etc = mkIf cfg.enable {
    devd.source = "${pkgs.freebsd.devd}/etc/devd";
  };
}

