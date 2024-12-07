{
  pkgs,
  config,
  lib,
  ...
}:

with lib;

let
  variableName = types.strMatching "[a-zA-Z_][a-zA-Z0-9_]*";

  maybeList = mkOptionType {
    name = "value or list of values";
    merge =
      loc: defs:
      let
        defs' = filterOverrides defs;
      in
      if any (def: isList def.value) defs' then
        concatMap (def: toList def.value) defs'
      else
        mergeEqualOption loc defs';
  };

  notNull = filterAttrs (_: value: value != null);

  cfg = config.freebsd.rc;

  formatRcConfLiteral =
    val:
    if val == true then
      "YES"
    else if val == false then
      "NO"
    else
      escapeShellArg val;

  formatRcConf =
    opts:
    concatStringsSep "\n" (mapAttrsToList (name: value: "${name}=${formatRcConfLiteral value}") opts);

  formatScriptLiteral = val: if builtins.isList val then escapeShellArgs val else escapeShellArg val;

  makeRcScript =
    opts:
    let
      defaultPath =
        if opts.bsdUtils then
          [
            pkgs.freebsd.bin
            pkgs.freebsd.limits
            pkgs.coreutils
          ]
        else
          [
            pkgs.coreutils
            pkgs.freebsd.bin
            pkgs.freebsd.limits
          ];
      fullPath = opts.path ++ defaultPath;
      pathStr = "${makeBinPath fullPath}:${makeSearchPathOutput "bin" "sbin" fullPath}";

    in
    pkgs.writeTextFile {
      inherit (opts) name;
      executable = true;
      text =
        ''
          #!${pkgs.runtimeShell}
        ''
        + concatStrings (
          mapAttrsToList (name: value: ''
            # ${name}: ${concatStringsSep " " value}
          '') opts.rcorderSettings
        )
        + lib.optionalString (opts.description != null) ''
          #  ${opts.description}
        ''
        + lib.optionalString (!opts.dummy) (
          ''

            export PATH=${escapeShellArg pathStr}

            . /etc/rc.subr
          ''
          + concatStringsSep "\n" (
            mapAttrsToList (name: value: "${name}=\"${formatScriptLiteral value}\"") (
              notNull opts.shellVariables
            )
          )
          + "\n"
          + concatStrings (
            mapAttrsToList (func_name: value: ''
              ${opts.name}_${func_name}() {
                ${value}
              }
            '') (notNull opts.hooks)
          )
          + ''

            load_rc_config ${opts.name}
            run_rc_command "$1"
          ''
        );
    };

  makeRcDir =
    scripts:
    pkgs.runCommand "rc.d" { } (
      ''
        mkdir -p $out
      ''
      + concatStrings (
        mapAttrsToList (name: script: ''
          ln -s ${makeRcScript script} $out/${script.name} 
        '') scripts
      )
    );

in
{
  options.freebsd.rc = {
    package = mkOption {
      type = types.package;
      default = pkgs.freebsd.rc;
      description = ''
        The FreeBSD rc package to use. Should contain `/etc/rc`, `/etc/rc.subr`, etc.
        See {manpage}`rc(8)`.
      '';
    };

    conf = mkOption {
      default = { };
      description = "Option set set in /etc/rc.conf";
      type = types.submodule {
        freeformType =
          with types;
          attrsOf (
            nullOr (oneOf [
              str
              bool
            ])
          );
        options = {
          root_rw_mount = mkOption {
            default = true;
            type = types.bool;
            description = "Whether to mount the root filesystem read/write.";
          };

          rc_info = mkOption {
            default = false;
            type = types.bool;
            description = "Whether to display informational messages at boot.";
          };

          rc_startmsgs = mkOption {
            default = true;
            type = types.bool;
            description = ''
              Whether to show "Starting service:" messages at boot.
            '';
          };
        };
      };
    };

    services = mkOption {
      default = { };
      description = "List of services to run. See `{manpage}`rc.subr(8).";
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            options = {
              name = mkOption {
                type = variableName;
                description = "Name of the service, also used for rc variables.";
              };

              description = mkOption {
                default = "";
                type = types.singleLineStr;
                description = "Description of service included in configuration file.";
              };

              dummy = mkOption {
                default = false;
                type = types.bool;
                description = ''
                  Whether to create a dummy service with no commands.
                  This is generally used for targets, like `NETWORKING`.
                '';
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

              bsdUtils = mkOption {
                default = false;
                type = types.bool;
                description = ''
                  Whether to use BSD binaries.
                  The default (false) is to use GNU coreutils.
                '';
              };

              environment = mkOption {
                default = { };
                type =
                  with types;
                  attrsOf (
                    nullOr (oneOf [
                      str
                      path
                      package
                    ])
                  );
                description = "Environment variables passed to the service's commands";
              };

              rcorderSettings = mkOption {
                description = "Settings used when ordering services with {manpage}`rcorder(8)`.";
                default = { };
                type = types.submodule {
                  freeformType = types.attrsOf (types.listOf variableName);
                  options = {
                    PROVIDE = mkOption {
                      default = [ ];
                      type = types.listOf variableName;
                      description = "Requirements provided by this service. Normally this is the service name.";
                    };
                    REQUIRE = mkOption {
                      default = [ ];
                      type = types.listOf variableName;
                      description = "Requirements to start the service.";
                    };
                    BEFORE = mkOption {
                      default = [ ];
                      type = types.listOf variableName;
                      description = "Services that will be started after this service.";
                    };
                    KEYWORD = mkOption {
                      default = [ ];
                      type = types.listOf variableName;
                      description = "Keywords that determine when this service is started, e.g. `nojail`.";
                    };
                  };
                  config = {
                    PROVIDE = [ name ];
                  };
                };
              };

              shellVariables = mkOption {
                description = ''
                  Shell variables to set after sourcing {path}`/etc/rc.subr`.
                  For a full list see `run_rc_command` under {manpage}`rc.subr(8)`.
                '';
                default = { };
                type = types.submodule {
                  freeformType = types.attrsOf maybeList;
                  config = {
                    name = mkOptionDefault name;
                    rcvar = mkOptionDefault "${name}_enable";
                  };
                };
              };

              namedShellVariables = mkOption {
                description = ''
                  Convenience alias for `shellVarables`.
                  Variable names are prefixed with `$${name}_`.
                '';
                default = { };
                type = types.submodule { freeformType = types.attrsOf maybeList; };
              };

              hooks = mkOption {
                description = ''
                  Shell text run when various events happen.
                  These are embedded in a function and the corresponding varaible is set.
                  See list under `run_rc_command` in {manpage}`rc.subr(8)`.
                '';
                default = { };
                type = types.submodule {
                  freeformType = with types; attrsOf (nullOr lines);

                  options = {
                    start_precmd = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Shell commands to run before starting the service.
                      '';
                    };
                    start_postcmd = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Shell commands to run after starting the service.
                      '';
                    };
                    stop_precmd = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Shell commands to run before stopping the service.
                      '';
                    };
                    stop_postcmd = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Shell commands to run after stopping the service.
                      '';
                    };
                  };
                };
              };
            };

            config = mkMerge [
              {
                name = mkOptionDefault name;
              }
              {
                shellVariables = mapAttrs' (
                  var: value: nameValuePair "${name}_${var}" value
                ) config.namedShellVariables;
              }
              {
                shellVariables = mapAttrs' (var: _: nameValuePair var "${name}_${var}") (notNull config.hooks);
              }
            ];
          }
        )
      );
    };
  };

  config = {
    freebsd.rc.conf = listToAttrs (
      map (service: nameValuePair service.shellVariables.rcvar true) (
        filter (service: !service.dummy) (attrValues cfg.services)
      )
    );

    environment.etc."rc" = {
      source = "${cfg.package}/etc/*";
      target = ".";
    };

    environment.etc."rc.conf".text = formatRcConf cfg.conf;
    environment.etc."rc.d".source = makeRcDir cfg.services;
  };
}
