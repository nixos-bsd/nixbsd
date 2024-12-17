{ pkgs, config, lib, ... }:
with lib;
let
  mkDefaultEnableOption = descr: (mkEnableOption descr) // { default = true; };
in {
  options.services = {
    DAEMON.enable = mkDefaultEnableOption "DAEMON stage";
    LOGIN.enable = mkDefaultEnableOption "LOGIN stage";
    FILESYSTEMS.enable = mkDefaultEnableOption "FILESYSTEMS stage";
    NETWORKING.enable = mkDefaultEnableOption "NETWORKING stage";
    SERVERS.enable = mkDefaultEnableOption "SERVERS stage";
  };

  imports = [
    {
      config = (mkIf config.services.DAEMON.enable {
        freebsd.rc.services.DAEMON = {
          rcorderSettings.REQUIRE = [ "NETWORKING" "SERVERS" ];
          dummy = true;
        };
      });
    }
    {
      config = (mkIf config.services.LOGIN.enable {
        freebsd.rc.services.LOGIN = {
          rcorderSettings.REQUIRE = [ "DAEMON" ];
          dummy = true;
        };
      });
    }
    {
      config = (mkIf config.services.FILESYSTEMS.enable {
        freebsd.rc.services.FILESYSTEMS = {
          rcorderSettings.REQUIRE = [ "root" "mountcritlocal" "cleanvar" "tmp" ];
          dummy = true;
        };
      });
    }
    {
      config = (mkIf config.services.NETWORKING.enable {
        freebsd.rc.services.NETWORKING = {
          rcorderSettings.PROVIDE = [ "NETWORK" ];
          # TODO
          #rcorderSettings.REQUIRE = ["netif" "netwait" "netoptions" "routing" "ppp" "ipfw" "stf" "defaultroute" "route6d" "resolv" "bridge" "static_arp" "static_ndp"];
          dummy = true;
        };
      });
    }
    {
      config = (mkIf config.services.SERVERS.enable {
        freebsd.rc.services.SERVERS = {
          # TODO
          #rcorderSettings.REQUIRE = ["mountcritremote" "sysvipc" "linux" "ldconfig" "savecore" "watchdogd"];
          dummy = true;
        };
      });
    }
  ];
}
