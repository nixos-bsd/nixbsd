{ config, pkgs, lib, ... }:
{
  options.services.consolekit2.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to enable consolekit2 for session management";
  };

  config = lib.mkIf config.services.consolekit2.enable {
    services.dbus.packages = [ pkgs.consolekit2 ];
    environment.systemPackages = [ pkgs.consolekit2 ];

    # seems to work better when dbus-activated
    #init.services.consolekit2 = {
    #  dependencies = ["DAEMON"];
    #  description = "Consolekit2 Session Manager";
    #  startCommand = [ "${pkgs.consolekit2}/bin/console-kit-daemon" "--no-daemon" "--debug"];
    #  startType = "foreground";
    #};
  };
}
