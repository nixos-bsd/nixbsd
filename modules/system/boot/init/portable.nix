{ lib, ... }:
with lib; {
  options = {
    init.backend = mkOption {
      type = types.str;
      example = "openrc";
      internal = true;
      description = ''
        Backend used to start specified services.
        This key should only be set by the backend and exists to prevent conflicts.
      '';
    };

    init.services = mkOption {
      default = { };
      description = "Services to instantiate";
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
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

          group = mkOption {
            type = types.nullOr types.passwdEntry types.str;
            default = null;
            description = "Name of the group to run the service as.";
          };

          startCommand = mkOption {
            type = types.listOf types.str;
            description = "Command to run to start the service";
          };

          startType = mkOption {
            type = types.enum [ "foreground" "forking" ];
            description = ''
              Method of starting service:
              * foreground: service runs in foreground, init system should handle running in background
              * forking: service forks and runs in background. May provide init system a pidfile
            '';
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
            type = types.nullOr types.listOf types.str;
            default = null;
            description =
              "Command to run to stop service. If null then the init system's default behavior applies";
          };

          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment variables to set when running commands";
          };

          dependencies = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description =
              "Services that must be started before starting this service";
          };

          overrides = mkOption {
            type = types.attrsOf types.attrsOf types.anything;
            default = { };
            description = "Backend-specific overrides";
          };
        };

        config = { name = mkDefault name; };
      }));
    };
  };
}
