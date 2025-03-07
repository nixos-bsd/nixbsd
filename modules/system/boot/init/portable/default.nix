{ lib, config, ... }:
with lib;
{
  options = {
    init.backend = mkOption {
      type = types.str;
      example = "openrc";
      description = ''
        Backend used to start specified services.
      '';
    };

    init.environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables to set when running any service.";
    };

    init.services = mkOption {
      default = { };
      description = "Services to instantiate";
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options = {
              name = mkOption {
                type = types.str;
                description = "Name of the service.";
              };

              description = mkOption {
                type = types.str;
                default = "";
                description = "Description of the service.";
              };

              user = mkOption {
                type = types.passwdEntry types.str;
                default = "root";
                description = "Name of the user to run service as.";
              };

              startCommand = mkOption {
                type = with types; listOf (either str package);
                description = "Command to run to start the service.";
              };

              startType = mkOption {
                type = types.enum [
                  "foreground"
                  "forking"
                  "oneshot"
                ];
                description = ''
                  Method of starting service:
                  * foreground: service runs in foreground, init system should handle running in background.
                  * forking: service forks and runs in background. Provides init system with a pidfile.
                  * oneshot: command exits quickly in normal use. Init system may block on startCommand.
                '';
              };

              pidFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "File created by the service containing the PID.";
              };

              directory = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Directory to cd to before starting.";
              };

              preStart = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Shell snippet to run before starting.";
              };

              postStart = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Shell snippet to run after starting.";
              };

              preStop = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Shell snippet to run before stopping.";
              };

              postStop = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Shell snippet to run after stopping.";
              };

              stopCommand = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Command to run to stop service. If null then the init system's default behavior applies.";
              };

              environment = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "Environment variables to set when running commands.";
              };

              path = mkOption {
                default = [ ];
                type =
                  with types;
                  listOf (oneOf [
                    package
                    str
                  ]);
                description = ''
                  Packages to add to the services {env}`PATH` environment variable.
                '';
              };

              dependencies = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Services that must be started before starting this service.";
              };

              before = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Services that depend on this service but do not declare it.";
              };

              defaultLog.enable = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to apply the system's typical logging mechanism to stdout and stderr.";
              };
              defaultLog.name = mkOption {
                type = types.str;
                description = "The key to use for the system's typical logging mechanism. Defaults to the service name.";
              };
            };

            config = lib.mkMerge [
              (lib.mkIf (config.startType == "oneshot") {
                defaultLog.enable = false;
              })
              {
                name = mkOptionDefault name;
                defaultLog.name = mkOptionDefault name;
              }];
          }
        )
      );
    };
  };

  config = {
    assertions = mapAttrsToList (name: cfg: {
      assertion = (cfg.startType == "foreground") -> (cfg.pidFile == null);
      message = ''
        Foreground service ${name} must not set a PID file.
      '';
    }) config.init.services;
  };
}
