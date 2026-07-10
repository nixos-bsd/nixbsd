{
  lib,
  config,
  freebsdPackages,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  _class = "service";
  imports = [
    (lib.mkAliasOptionModule [ "freebsd" "rc" "service" ] [ "freebsd" "rc" "services" "" ])
  ];
  options = {
    freebsd.rc.mainCommand = mkOption {
      description = ''
        Command to run for the main program.
        It should execute as a foreground process, as it will be run through {manpage}`daemon(3)`.
      '';
      type = types.listOf types.str;
      default = config.process.argv;
      defaultText = lib.literalExpression "config.process.argv";
    };

    freebsd.rc.services = mkOption {
      description = ''
        This module configures freebsd.rc services, with the notable difference that their unit names will be prefixed with the abstract service name.

        This option's value is not suitable for reading, but you can define a module here that interacts with just the unit configuration in the host system configuration.

        Note that this option contains _deferred_ modules.
        This means that the module has not been combined with the system configuration yet, no values can be read from this option.
        What you can do instead is define a module that reads from the module arguments (such as `config`) that are available when the module is merged into the system configuration.
      '';
      type = types.lazyAttrsOf (
        types.deferredModuleWith {
          staticModules = [
            # TODO: Add modules for the purpose of generating documentation?
          ];
        }
      );
      default = { };
    };

    # Also import freebsd.rc logic into sub-services
    # extends the portable `services` option
    services = mkOption {
      type = types.attrsOf (
        types.submoduleWith {
          class = "service";
          modules = [
            ./service.nix
          ];
          specialArgs = {
            inherit freebsdPackages;
          };
        }
      );
      # Rendered by the portable docs instead.
      visible = false;
    };
  };
  config = {
    # Note that this is the freebsd.rc.services option above, not the system one.
    freebsd.rc.services."" = {
      rcorderSettings.REQUIRE = [ "DAEMON" ];
      shellVariables = rec {
        command = "${freebsdPackages.daemon}/bin/daemon";
        command_args = [
          "-u"
          config.freebsd.meta.username
          "-P"
          pidfile
          "--"
        ]
        ++ config.freebsd.rc.mainCommand;

        pidfile = "/run/modular-${config.freebsd.meta.servicePrefix}.pid";
      };
    };
  };
}
