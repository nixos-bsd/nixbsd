{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  variableName = types.strMatching "[a-zA-Z_][a-zA-Z0-9_]*";
  formatScriptLiteral = val: if builtins.isList val then escapeShellArgs val else escapeShellArg val;
  notNull = filterAttrs (_: value: value != null);
  cfg = config.openbsd.rc;

  makeRcOrder = services: let
    dummyServiceNames = [
      /* 05 */ [ "FILESYSTEMS" "hostname" "fsck" "swap" "mount-basic" "ttyflags" "kbd" "wsconctl_conf" "temp-pf" "baddynamic" "sysctl" ]
      /* 15 */ [ "ifconfig" "netstart" ]
      /* 25 */ [ "NETWORKING" "random_seed" "pf" "early-cleanup" "dmesg-boot" "make-keys" ]
      /* 35 */ [ "SERVERS" "ipsec" ]
      /* 45 */ [ "DAEMON" "mount-final" "swap-noblk" "fsck-N" "mount-N" "kvm-mkdb" "dev-mkdb" "savecore" "acpidump" "quotacheck" "wuotaon" "chown-chmod-tty" "ptmp" "clean-tmp" "socket-tmpdirs" "securelevel" "motd" "accounting" "ldconfig" "vi-recover" "sysmerge" ]
      /* 55 */ [ "LOGIN" "firsttime" ]
      /* 65 */ [ "carpdemote" "mixerctl-conf" ]
    ];
    dummyServices = imap0 (i: svclist: let prio = i * 10 + 5; in { inherit prio; name = "__dummy_${builtins.toString prio}"; aliases = svclist; DUMMY = true; before = []; after = []; }) dummyServiceNames;
    servicesLst = dummyServices ++ mapAttrsToList (name: opts: opts // { aliases = []; }) services;
    sorter = a: b: let
      aBeforeB = builtins.elem a.name b.after || any (alias: builtins.elem alias b.after) a.aliases;
      bAfterA = builtins.elem b.name a.before || any (alias: builtins.elem alias a.before) b.aliases;
      dummyBefore = if (a.DUMMY or false) && (b.DUMMY or false) then a.prio < b.prio else false;
    in /* builtins.trace "${a.name} -> ${b.name}: ${formatRcConfLiteral aBeforeB} ${formatRcConfLiteral bAfterA} ${formatRcConfLiteral dummyBefore}" */ (bAfterA || aBeforeB || dummyBefore);
    sortedRaw = toposort sorter servicesLst;
    sorted = sortedRaw.result or (throw "Service dependency loop: cycle = ${concatMapStringsSep " " (svc: svc.name) sortedRaw.cycle}; loops = ${concatMapStringsSep " " (svc: svc.name) sortedRaw.loops};");
    initialState = { current = 0; phases = {}; };
    folder = state: svc: if svc.DUMMY or false then { phases = state.phases // { ${builtins.toString (state.current + 10)} = []; }; current = state.current + 10; } else { inherit (state) current; phases = state.phases // { ${builtins.toString state.current} = (state.phases.${builtins.toString state.current} or []) ++ [ svc ]; }; };
    phases = (foldl folder initialState sorted).phases;
  in pkgs.runCommand "rc.order" { } (
    ''
      mkdir -p $out
    '' + concatStrings (
      mapAttrsToList (phase: services: let
        text = concatMapStringsSep "\n" (service: "start_daemon ${service}") (builtins.map (svc: svc.name) services);
        drv = pkgs.writeTextFile { name = "phase_${phase}"; inherit text; };
      in ''
        ln -s ${drv} $out/${phase}
      ''
      ) phases
    )
  );
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
    makeRcScript = opts:
    let
      defaultPath = [ pkgs.coreutils ];
      fullPath = opts.path ++ defaultPath;
      pathStr = "${makeBinPath fullPath}:${makeSearchPathOutput "bin" "sbin" fullPath}";
    in pkgs.writeTextFile {
      inherit (opts) name;
      executable = true;
      text = ''
        #!${pkgs.runtimeShell}
      '' + lib.optionalString (opts.description != null) ''
        #  ${opts.description}
      '' + ''
        export PATH=${escapeShellArg pathStr}
        daemon=${escapeShellArg opts.daemon}
  
        . /etc/rc.subr
      '' + lib.concatStringsSep "\n" (
        mapAttrsToList (name: value: "${name}=\"${formatScriptLiteral value}\"") (
          notNull opts.shellVariables
        )
      ) + lib.concatStringsSep "\n" (
        mapAttrsToList (name: value: "export ${name}=\"${formatScriptLiteral value}\"") (
          notNull opts.environment
        )
      ) + "\n" + lib.concatStrings (
        mapAttrsToList (func_name: value: ''
          ${func_name}() {
            ${value}
          }
        '') (notNull opts.hooks)
      ) + ''

        ${opts.extraConfig}

        rc_cmd "$1"
      '';
    };
in {
  options.openbsd.rc = {
    package = mkOption {
      type = types.package;
      default = pkgs.openbsd.rc;
      description = ''
        The OpenBSD rc package to use. Should contain `/etc/rc`, `/etc/rc.subr`, etc.
        See {manpage}`rc(8)`.
      '';
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

              daemon = mkOption {
                type = types.pathInStore;
                description = "Path to the executable to launch for this service.";
              };


              dummy = mkOption {
                default = null;
                type = types.nullOr types.int;
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

              extraConfig = mkOption {
                default = "";
                type = types.lines;
                description = ''
                  Extra functions added to the end of the configuration.
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

              before = mkOption {
                description = "Names of services which should be started after this service";
                default = [];
                type = types.listOf types.str;
              };
              after = mkOption {
                description = "Names of services which should be before this service";
                default = [];
                type = types.listOf types.str;
              };

              shellVariables = mkOption {
                description = ''
                  Shell variables to set after sourcing {path}`/etc/rc.subr`.
                  For a full list see {manpage}`rc.subr(8)`.
                '';
                default = { };
                type = types.submodule {
                  freeformType = types.attrsOf maybeList;
                  options = {
                    daemon_execdir = mkOption {
                      default = "/";
                      type = types.nullOr types.str;
                      description = "Directory to use as cwd during service execution.";
                    };
                    daemon_flags = mkOption {
                      default = "";
                      type = types.oneOf [ types.str (types.listOf types.str) ];
                      description = "Command line flags to use for launching the service.";
                    };
                    daemon_logger = mkOption {
                      default = "";
                      type = types.str;
                      description = "Redirect standard output and error to logger(1) using the configured priority (e.g. \"daemon.info\").";
                    };
                    daemon_rtable = mkOption {
                      default = "0";
                      type = types.str;
                      description = "Routing table to run the service under, using route(8).";
                    };
                    daemon_timeout = mkOption {
                      default = "30";
                      type = types.str;
                      description = "Maximum time in seconds to wait for the start, stop and reload actions to return.";
                    };
                    daemon_user = mkOption {
                      default = "root";
                      type = types.str;
                      description = "User to run the daemon as, using su(1).";
                    };
                    pexp = mkOption {
                      default = null;
                      type = types.nullOr types.str;
                      description = "A regular expression to be passed to pgrep(1) in order to find the desired process or to be passed to pkill(1) to stop it.";
                    };
                    rc_bg = mkOption {
                      default = false;
                      type = types.bool;
                      description = "Can be set to YES in an rc.d script to force starting the daemon in background when using the default rc_start.";
                    };
                    rc_reload = mkOption {
                      default = true;
                      type = types.bool;
                      description = "Can be set to “NO” in an rc.d script to disable the reload action if the respective daemon does not support reloading its configuration.";
                    };
                    rc_reload_signal = mkOption {
                      default = "HUP";
                      type = types.str;
                      description = "Signal sent to the daemon process (pexp) by the default rc_reload() function.";
                    };
                    rc_stop_signal = mkOption {
                      default = "HUP";
                      type = types.str;
                      description = "Signal sent to the daemon process (pexp) by the default rc_stop() function.";
                    };
                    rc_usercheck = mkOption {
                      default = true;
                      type = types.bool;
                      description = "Can be set to “NO” in an rc.d script, if the check action needs root privileges.";
                    };
                  };
                };
              };

              hooks = mkOption {
                description = ''
                  Shell text run when various events happen.
                  These are embedded in a function and the corresponding varaible is set.
                  See list in {manpage}`rc.subr(8)`.
                '';
                default = { };
                type = types.submodule {
                  freeformType = with types; attrsOf (nullOr lines);

                  options = {
                    rc_check = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Search for processes of the service with pgrep(1) using the regular expression given in the pexp variable.
                      '';
                    };
                    rc_configtest = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Check daemon configuration before running start, reload and restart if implemented by the rc.d(8) script.
                      '';
                    };
                    rc_exec = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Execute argument using su(1) according to daemon_class, daemon_execdir, daemon_user, daemon_rtable and daemon_logger values.
                      '';
                    };
                    rc_post = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        This function is run after stop if implemented by the rc.d(8) script.
                      '';
                    };
                    rc_pre = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        This function is run before start if implemented by the rc.d(8) script.
                      '';
                    };
                    rc_reload = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Send the rc_reload_signal using pkill(1) on the regular expression given in the pexp variable.  One has to make sure that sending SIGHUP to a daemon will have the desired effect, i.e. that it will reload its configuration.
                      '';
                    };
                    rc_start = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Start the daemon.  Defaults to:

                        rc_exec "''${daemon} ''${daemon_flags}"
                      '';
                    };
                    rc_stop = mkOption {
                      default = null;
                      type = types.nullOr types.lines;
                      description = ''
                        Stop the daemon.  Send the rc_stop_signal using pkill(1) on the regular expression given in the pexp variable.
                      '';
                    };
                  };
                };
              };
            };

            config = mkMerge [
              {
                name = mkOptionDefault (builtins.replaceStrings [ "-" ] [ "_" ] name);
              }
            ];
          }
        )
      );
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

  };
  config = {
    openbsd.rc.conf = listToAttrs (
      mapAttrsToList (name: service: nameValuePair "${service.name}_flags" "") cfg.services
    );

    environment.etc."rc" = {
      source = "${cfg.package}/etc/*";
      target = ".";
    };

    environment.etc."rc.order".source = makeRcOrder cfg.services;
    environment.etc."rc.conf".text = formatRcConf cfg.conf;
    environment.etc."rc.d".source = makeRcDir cfg.services;
  };
}
