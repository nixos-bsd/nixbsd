{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
let
  convertService =
    name: cfg:
    {
      provides = cfg.name;
      description = cfg.description;
      requires = cfg.dependencies;
    }
    // (
      if (cfg.startType == "foreground") then
        {
          # "Foreground" means we have to run in the background with daemon
          command = "${pkgs.freebsd.daemon}/bin/daemon";
          command_args = [
            "-u"
            cfg.user
            "-P"
            pidFile
            "-S"
            "--"
          ] ++ cfg.startCommand;
        }
      else
        {

        }
    );
in
{
  config = mkMerge [
    { init.backend = mkOptionDefault "freebsd"; }
    (mkIf (config.init.backend == "freebsd") {
      rc.services = lib.mapAttrs convertService config.init.services;
    })
  ];
}
