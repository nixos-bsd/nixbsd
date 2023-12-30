{ pkgs, config, lib, ... }: with lib;
let 
  mkDefaultEnableOption = descr: (mkEnableOption descr) // { default = true; };
in
{
  options.services = {
    DAEMON.enable = mkDefaultEnableOption "DAEMON stage";
    LOGIN.enable = mkDefaultEnableOption "LOGIN stage";
    FILESYSTEMS.enable = mkDefaultEnableOption "FILESYSTEMS stage";
    NETWORKING.enable = mkDefaultEnableOption "NETWORKING stage";
    SERVERS.enable = mkDefaultEnableOption "SERVERS stage";
  };

  imports = [
    { config = (mkIf config.services.DAEMON.enable {
      rc.services.DAEMON = {
        provides = "DAEMON";
        requires = ["NETWORKING" "SERVERS"];
        dummy = true;
      };
    });}
    { config = (mkIf config.services.LOGIN.enable {
      rc.services.LOGIN = {
        provides = "LOGIN";
        requires = ["DAEMON"];
        dummy = true;
      };
    });}
    { config = (mkIf config.services.FILESYSTEMS.enable {
      rc.services.FILESYSTEMS = {
        provides = "FILESYSTEMS";
        requires = ["root" "mountcritlocal" "cleanvar" "tmp"];
        dummy = true;
      };
    });}
    { config = (mkIf config.services.NETWORKING.enable {
      rc.services.NETWORKING = {
        provides = ["NETWORKING" "NETWORK"];
        # TODO
        #requires = ["netif" "netwait" "netoptions" "routing" "ppp" "ipfw" "stf" "defaultroute" "route6d" "resolv" "bridge" "static_arp" "static_ndp"];
        dummy = true;
      };
    });}
    {config = (mkIf config.services.SERVERS.enable {
      rc.services.SERVERS = {
        provides = "SERVERS";
        # TODO
        #requires = ["mountcritremote" "sysvipc" "linux" "ldconfig" "savecore" "watchdogd"];
        dummy = true;
      };
    });}
  ];
}
