{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
let
  convertService = name: cfg: {
    name = builtins.replaceStrings [ "-" ] [ "_" ] cfg.name;
    description = cfg.description;
    rcorderSettings = {
      REQUIRE = cfg.dependencies;
      BEFORE = cfg.before;
    };

    inherit (cfg) path;

    shellVariables =
      optionalAttrs (cfg.startType == "foreground") {
        command = "${pkgs.freebsd.daemon}/bin/daemon";
        command_args = [
          "-u"
          cfg.user
          "-P"
          "/var/run/${cfg.name}.pid"
          "-S"
          "--"
        ] ++ cfg.startCommand;

        pidfile = "/var/run/${cfg.name}.pid";
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
        "${cfg.name}_chdir" = cfg.directory;
      }
      // optionalAttrs (cfg.environment != null) {
        "${cfg.name}_env_file" = pkgs.writeText "${cfg.name}-env" (toShellVars cfg.environment);
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
