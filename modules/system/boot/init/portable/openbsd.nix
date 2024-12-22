{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
let
  convertService = name: cfg: {
    inherit (cfg) environment description path;
    name = builtins.replaceStrings [ "-" ] [ "_" ] cfg.name;
    daemon = head cfg.startCommand;
    shellVariables.daemon_flags = tail cfg.startCommand;
    shellVariables.rc_bg = cfg.startType == "foreground";
    shellVariables.daemon_execdir = cfg.directory;
    hooks.stop_cmd = if cfg.startType == "oneshot" then ":" else null;
    hooks = {
      rc_pre = cfg.preStart;
      rc_post = cfg.postStop;
      rc_start = if cfg.postStart == null then null else ''
        rc_exec "''${daemon} ''${daemon_flags}"
        ${cfg.postStart}
      '';
      rc_stop = if cfg.preStop == null then null else ''
        ${cfg.preStop}
        _rc_sendsig ''${rc_stop_signal}
      '';
    };
    before = cfg.before;
    after = cfg.dependencies;
  };
in
{
  config = mkMerge [
    { init.backend = mkOptionDefault "openbsd"; }
    (mkIf (config.init.backend == "openbsd") {
      openbsd.rc.services = lib.mapAttrs convertService config.init.services;
    })
  ];
}
