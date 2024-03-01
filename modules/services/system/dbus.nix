# D-Bus configuration and system bus daemon.

{ config, lib, pkgs, ... }:

let

  cfg = config.services.dbus;

  homeDir = "/run/dbus";

  configDir = pkgs.makeDBusConf {
    inherit (cfg) apparmor;
    suidHelper = "${config.security.wrapperDir}/dbus-daemon-launch-helper";
    serviceDirectories = cfg.packages;
  };

  inherit (lib) mkOption mkIf mkMerge types;

in

{
  options = {

    services.dbus = {

      enable = mkOption {
        type = types.bool;
        default = false;
        internal = true;
        description = lib.mdDoc ''
          Whether to start the D-Bus message bus daemon, which is
          required by many other system services and applications.
        '';
      };

      implementation = mkOption {
        type = types.enum [ "dbus" "broker" ];
        default = "dbus";
        description = lib.mdDoc ''
          The implementation to use for the message bus defined by the D-Bus specification.
          Can be either the classic dbus daemon or dbus-broker, which aims to provide high
          performance and reliability, while keeping compatibility to the D-Bus
          reference implementation.
        '';

      };

      packages = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = lib.mdDoc ''
          Packages whose D-Bus configuration files should be included in
          the configuration of the D-Bus system-wide or session-wide
          message bus.  Specifically, files in the following directories
          will be included into their respective DBus configuration paths:
          {file}`«pkg»/etc/dbus-1/system.d`
          {file}`«pkg»/share/dbus-1/system.d`
          {file}`«pkg»/share/dbus-1/system-services`
          {file}`«pkg»/etc/dbus-1/session.d`
          {file}`«pkg»/share/dbus-1/session.d`
          {file}`«pkg»/share/dbus-1/services`
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.etc."dbus-1".source = configDir;

      environment.pathsToLink = [
        "/etc/dbus-1"
        "/share/dbus-1"
      ];

      users.users.messagebus = {
        uid = config.ids.uids.messagebus;
        description = "D-Bus system message bus daemon user";
        home = homeDir;
        homeMode = "0755";
        group = "messagebus";
      };

      users.groups.messagebus.gid = config.ids.gids.messagebus;

      services.dbus.packages = [
        pkgs.dbus
        config.system.path
      ];

      rc.services.dbus = {
        provides = "dbus";
        command = "${pkgs.dbus}/bin/dbus-daemon";
        hasPidfile = true;
        requres = ["DAEMON" "ldconfig"];
        precmds = {
          start = ''
            mkdir -p /var/lib/dbus
            ${pkgs.dbus}/bin/dbus-uuidgen --ensure
            mkdir -p /var/run/dbus
          '';
        };
        environment = {
          dbus_flags = "--system";
        };
      };
    }

    (mkIf (cfg.implementation == "dbus") {
      environment.systemPackages = [
        pkgs.dbus
      ];

      security.wrappers.dbus-daemon-launch-helper = {
        source = "${pkgs.dbus}/libexec/dbus-daemon-launch-helper";
        owner = "root";
        group = "messagebus";
        setuid = true;
        setgid = false;
        permissions = "u+rx,g+rx,o-rx";
      };

    })

    (mkIf (cfg.implementation == "broker") {
      environment.systemPackages = [
        pkgs.dbus-broker
      ];

    })

  ]);
}
