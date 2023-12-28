{ pkgs, config, lib, ... }: with lib;
let 
  mkDefaultEnableOption = descr: (mkEnableOption descr) // { default = true; };
  stages = ["DAEMON" "LOGIN" "FILESYSTEMS" "NETWORKING" "SERVERS"];
in
{
  options.services = {
    DAEMON.enable = mkDefaultEnableOption "DAEMON stage";
    LOGIN.enable = mkDefaultEnableOption "LOGIN stage";
    FILESYSTEMS.enable = mkDefaultEnableOption "FILESYSTEMS stage";
    NETWORKING.enable = mkDefaultEnableOption "NETWORKING stage";
    SERVERS.enable = mkDefaultEnableOption "SERVERS stage";
  };

  config = (mkIf config.services.DAEMON.enable {
    rc.entries.DAEMON = {
      provides = "DAEMON";
      requires = ["NETWORKING" "SERVERS"];
      dummy = true;
    };
  }) // (mkIf config.services.LOGIN.enable {
    rc.entries.LOGIN = {
      provides = "LOGIN";
      requires = ["DAEMON"];
      dummy = true;
    };
  }) // (mkIf config.services.FILESYSTEMS.enable {
    rc.entries.FILESYSTEMS = {
      provides = "FILESYSTEMS";
      requires = ["root" "mountcritlocal" "cleanvar" "tmp"];
      dummy = true;
    };
  }) // (mkIf config.services.NETWORKING.enable {
    rc.entries.NETWORKING = {
      provides = ["NETWORKING" "NETWORK"];
      # TODO
      #requires = ["netif" "netwait" "netoptions" "routing" "ppp" "ipfw" "stf" "defaultroute" "route6d" "resolv" "bridge" "static_arp" "static_ndp"];
      dummy = true;
    };
  }) // (mkIf config.services.SERVERS.enable {
    rc.entries.SERVERS = {
      provides = "SERVERS";
      # TODO
      #requires = ["mountcritremote" "sysvipc" "linux" "ldconfig" "savecore" "watchdogd"];
      dummy = true;
    };
  });
}
