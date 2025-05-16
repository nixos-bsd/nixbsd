{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
let
  convertName = builtins.replaceStrings [ "-" ] [ "_" ];
  convertService = name: cfg: {
    name = convertName cfg.name;
    description = cfg.description;
    rcorderSettings = {
      REQUIRE = builtins.map convertName cfg.dependencies;
      BEFORE = builtins.map convertName cfg.before;
      PROVIDE = builtins.map convertName cfg.provides;
      KEYWORDS = lib.optionals (!cfg.onSwitch) [ "noswitch" ];
    };

    inherit (cfg) path defaultLog;

    shellVariables =
      optionalAttrs (cfg.startType == "foreground") {
        command = "${pkgs.freebsd.daemon}/bin/daemon";
        command_args = [
          "-u"
          cfg.user
          "-P"
          "/run/${cfg.name}.pid"
        ] ++ lib.optionals (!cfg.defaultLog.enable) [
          "-S"
        ] ++ [
          "--"
        ] ++ cfg.startCommand
        ;

        pidfile = "/run/${cfg.name}.pid";
      }
      // {
        sig_stop = cfg.stopSignal;
      }
      // optionalAttrs (cfg.startType == "forking" || cfg.startType == "oneshot") {
        command = head cfg.startCommand;
        command_args = tail cfg.startCommand;
      }
      // optionalAttrs (cfg.startType == "oneshot") {
        stop_cmd = ":";
      }
      // optionalAttrs (cfg.pidFile != null) {
        pidfile = cfg.pidFile;
      }
      // optionalAttrs (cfg.directory != null) {
        "${convertName cfg.name}_chdir" = cfg.directory;
      }
      // optionalAttrs (cfg.environment != null) {
        "${convertName cfg.name}_env_file" = pkgs.writeText "${cfg.name}-env" (toShellVars cfg.environment);
      };

    hooks = {
      start_precmd = cfg.preStart;
      start_postcmd = cfg.postStart;
      stop_precmd = cfg.preStop;
      stop_postcmd = cfg.postStop;
    };
  };
in
{
  config = mkMerge [
    { init.backend = mkOptionDefault "freebsd"; }
    (mkIf (config.init.backend == "freebsd") {
      freebsd.rc.services = lib.mapAttrs convertService config.init.services;
    })
  ];
}
