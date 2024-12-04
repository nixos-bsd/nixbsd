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
                description = "Name of the service";
              };

              description = mkOption {
                type = types.str;
                default = "";
                description = "Description of the service";
              };

              user = mkOption {
                type = types.passwdEntry types.str;
                default = "root";
                description = "Name of the user to run service as";
              };

              startCommand = mkOption {
                type = types.listOf types.str;
                description = "Command to run to start the service";
              };

              startType = mkOption {
                type = types.enum [
                  "foreground"
                  "forking"
                ];
                description = ''
                  Method of starting service:
                  * foreground: service runs in foreground, init system should handle running in background
                  * forking: service forks and runs in background. Provides init system with a pidfile
                '';
              };

              pidFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "File created by the service containing the PID";
              };

              directory = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Directory to cd to before starting";
              };

              preStart = mkOption {
                type = types.lines;
                default = null;
                description = "Shell snippet to run before starting";
              };

              postStart = mkOption {
                type = types.lines;
                default = null;
                description = "Shell snippet to run after starting";
              };

              preStop = mkOption {
                type = types.lines;
                default = null;
                description = "Shell snippet to run before stopping";
              };

              postStop = mkOption {
                type = types.lines;
                default = null;
                description = "Shell snippet to run after stopping";
              };

              stopCommand = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Command to run to stop service. If null then the init system's default behavior applies";
              };

              environment = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "Environment variables to set when running commands";
              };

              dependencies = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Services that must be started before starting this service";
              };
            };

            config = {
              name = mkOptionDefault name;
            };
          }
        )
      );
    };
  };

  config = {
    assertions =
      (mapAttrsToList (name: cfg: {
        assertion = (cfg.startType == "forking") -> (cfg.PIDFile != null);
        message = ''
          Forking service ${name} must set a PID file.
        '';
      }) config.init.services)
      ++ (mapAttrsToList (name: cfg: {
        assertion = (cfg.startType == "foreground") -> (cfg.PIDFile == null);
        message = ''
          Foreground service ${name} must not set a PID file.
        '';
      }) config.init.services);
  };
}
