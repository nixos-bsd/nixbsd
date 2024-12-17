{ config, lib, utils, pkgs, ... }:

with lib;

let

  cfg = config.services.devd;

in {
  options.services.devd = {
    enable = mkEnableOption "devd service";
  };

  config = mkIf cfg.enable {
    init.services.devd = {
      description = "Device Daemon";
      before = [ "NETWORKING" ];

      startType = "forking";
      pidFile = "/var/run/devd.pid";
      startCommand = [ "${pkgs.freebsd.devd}/bin/devd" ];
      preStart = ''
        if ! checkyesno devd_enable; then
          sysctl hw.bus.devctl_queue=0
        fi
        mkdir -p /run/dbus
      '';
    };
    environment.etc = {
      devd.source = "${pkgs.freebsd.devd}/etc/devd";
      "devd.conf".text = ''
        options {
          directory "/etc/devd";
          pid-file "/var/run/devd.pid";
        };
      '';
    };
  };
}

