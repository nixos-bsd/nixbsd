{ config, lib, utils, pkgs, ... }:

with lib;

let

  cfg = config.services.devd;

in {
  options.services.devd = {
    enable = mkEnableOption "devd service" // { default = true; };
    rules = lib.mkOption {
      description = "An map of rules, each of which corresponds to a block of text in the devd.conf syntax.";
      default = {};
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          text = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Literal text to put in the configuration";
            default = null;
          };
          source = lib.mkOption {
            type = lib.types.nullOr lib.types.pathInStore;
            description = "File of configuration to include";
            default = null;
          };
        };
      });
    };
  };

  config = mkIf cfg.enable {
    services.devd.rules = {
      devmatch.source = "${pkgs.freebsd.devd.etc}/etc/devd/devmatch.conf";
      asus.source = "${pkgs.freebsd.devd.etc}/etc/devd/asus.conf";
      autofs.source = pkgs.runCommand "autofs.conf" {} ''
        sed -E -e 's_/usr/sbin/__g' <"${pkgs.freebsd.devd.etc}/etc/devd/autofs.conf" >$out
      '';
      bluetooth.source = "${pkgs.freebsd.devd.etc}/etc/devd/bluetooth.conf";
      dhclient.source = "${pkgs.freebsd.devd.etc}/etc/devd/dhclient.conf";
      moused.source = "${pkgs.freebsd.devd.etc}/etc/devd/moused.conf";
      nvmf.source = "${pkgs.freebsd.devd.etc}/etc/devd/nvmf.conf";
      power_profile.source = "${pkgs.freebsd.devd.etc}/etc/devd/power_profile.conf";
      syscons.source = "${pkgs.freebsd.devd.etc}/etc/devd/syscons.conf";
      uath.source = pkgs.runCommand "uath.conf" {} ''
        sed -E -e 's_/usr/sbin/__g' <"${pkgs.freebsd.devd.etc}/etc/devd/uath.conf" >$out
      '';
      ulpt.source = "${pkgs.freebsd.devd.etc}/etc/devd/ulpt.conf";
      zfs.source = "${pkgs.freebsd.devd.etc}/etc/devd/zfs.conf";
    };

    init.services.devd = {
      description = "Device Daemon";
      before = [ "NETWORKING" ];
      dependencies = [ "FILESYSTEMS" "sysctl" ];
      path = [ "/run/current-system/sw" pkgs.freebsd.devmatch ];

      startType = "forking";
      pidFile = "/run/devd.pid";
      startCommand = [ "${pkgs.freebsd.devd}/bin/devd" ];
      preStart = ''
        if ! checkyesno devd_enable; then
          sysctl hw.bus.devctl_queue=0
        fi
        mkdir -p /run/dbus
      '';
    };

    freebsd.rc.services.power_profile.source = "${pkgs.freebsd.rc.services}/etc/rc.d/power_profile";
    freebsd.rc.services.devmatch.source = "${pkgs.freebsd.rc.services}/etc/rc.d/devmatch";

    environment.etc = {
      "devd.conf".source = "${pkgs.freebsd.devd}/etc/devd.conf";
    } // (lib.mapAttrs' (name: val: { name = "devd/${name}.conf"; value = if val.text != null then { inherit (val) text; } else { inherit (val) source; }; }) cfg.rules);
  };
}

