{ pkgs, config, lib, ... }:
with lib;
let
  identType = types.strMatching "[_a-zA-Z][_a-zA-Z0-9]*";
  defaultCommands = [
    "start"
    "stop"
    "restart"
    "status"
    "enable"
    "disable"
    "delete"
    "describe"
    "extracommands"
    "poll"
    "enabled"
    "rcvar"
  ];
  cfg = config.rc;
  mkRcScript = { provides, command, commandArgs, shell, requires, before
    , keywords, hasPidfile, commands, dummy, description, binDeps, procname
    , defaultBinDeps, environment, extraConfig, precmds, postcmds, ... }:
    let
      extraCommands =
        builtins.attrNames (builtins.removeAttrs commands defaultCommands);
      definedCommands = filterAttrs (k: v: v != null) commands;
      definedEnvironment = filterAttrs (k: v: v != null) environment;
      name = if (builtins.isString provides) then
        provides
      else
        builtins.elemAt provides 0;
    in pkgs.writeTextFile {
      inherit name;
      executable = true;
      text = ''
        #!${shell}${shell.shellPath or ""}
        # This file generated by nixbsd. It is not bespoke configuration! Do not modify!

        # PROVIDE: ${
          if (builtins.isString provides) then
            provides
          else
            (concatStringsSep " " provides)
        }
      '' + optionalString ((builtins.length requires) != 0) ''
        # REQUIRE: ${concatStringsSep " " requires}
      '' + optionalString ((builtins.length before) != 0) ''
        # BEFORE: ${concatStringsSep " " before}
      '' + optionalString ((builtins.length keywords) != 0) ''
        # KEYWORD: ${concatStringsSep " " keywords}
      '' + optionalString ((builtins.stringLength description) != 0) ''
        # DESCRIPTION: ${description}
      '' + optionalString (!dummy) (''

        export PATH=${makeBinPath (binDeps ++ defaultBinDeps)}:$PATH
        . /etc/rc.subr

        name="${name}"
        rcvar="${name}_enable"
        ${concatStringsSep "\n"
        (mapAttrsToList (k: v: "export " + toShellVar k v) definedEnvironment)}
      '' + optionalString (command != null) ''
        command="${command}"
      '' + optionalString (builtins.length commandArgs != 0) ''
        command_args="${escapeShellArgs commandArgs}"
      '' + optionalString (procname != null) ''
        procname="${procname}"
      '' + optionalString hasPidfile ''
        pidfile="/var/run/${name}.pid"
      '' + optionalString ((builtins.length extraCommands) != 0) ''
        extra_commands="${concatStringsSep " " extraCommands}"
      '' + concatStringsSep "" (mapAttrsToList (cmd_name: cmd_value: ''
        ${cmd_name}_cmd="${name}_${cmd_name}"
      '') definedCommands)
      + concatStringsSep "" (mapAttrsToList
        (cmd_name: cmd_value: ''
          ${cmd_name}_precmd="${name}_${cmd_name}_precmd"
        '') precmds) + "\n"
      + concatStringsSep "" (mapAttrsToList
        (cmd_name: cmd_value: ''
          ${cmd_name}_postcmd="${name}_${cmd_name}_postcmd"
        '') postcmds) + "\n"
      + concatStringsSep "\n" (mapAttrsToList
        (cmd_name: cmd_value: ''
          ${name}_${cmd_name}() {
          ${cmd_value}
          }
        '') definedCommands)
      + concatStringsSep "\n" (mapAttrsToList
        (cmd_name: cmd_value: ''
          ${name}_${cmd_name}_precmd() {
          ${cmd_value}
          }
        '') precmds)
      + concatStringsSep "\n" (mapAttrsToList
        (cmd_name: cmd_value: ''
          ${name}_${cmd_name}_postcmd() {
          ${cmd_value}
          }
        '') postcmds)
      + ''
        ${extraConfig}

        load_rc_config ${name}
        run_rc_command "$1"
      '');
    };
  mkRcDir = scriptCfg:
    pkgs.runCommand "rc.d" {} (''
      mkdir -p $out
    '' + lib.concatStringsSep "" (builtins.map (target: ''
      ln -s ${mkRcScript target} $out/${if (builtins.isString target.provides) then target.provides else builtins.elemAt target.provides 0}
    '') scriptCfg));
  mkRcBool = b: if b then "YES" else "NO";
  mkRcLiteral = val:
    "'" + (replaceStrings [ "'" ] [ "'\"'\"'" ]
      (if (builtins.isBool val) then (mkRcBool val) else val)) + "'";
  mkRcConf = options:
    pkgs.writeTextFile {
      name = "rc.conf";
      text = concatStringsSep "\n" ([ "#!/bin/sh" ]
        ++ (mapAttrsToList (key: val: "${key}=${mkRcLiteral val}") options));
    };
in {
  options.rc.enabled = (mkEnableOption "rc") // { default = true; };
  options.rc.package = mkOption {
    type = types.package;
    default = pkgs.freebsd.rc;
    description =
      "The FreeBSD rc package to use. Expected contents: /etc/rc, /etc/rc.subr, ...";
  };
  options.rc.services = mkOption {
    default = { };
    description = "Definition of rc services";
    type = types.attrsOf (types.submodule ({ config, ... }: {
      options.provides = mkOption {
        type = types.either identType (types.listOf identType);
        description = "The name of the service. Gets used as a variable name.";
      };

      options.description = mkOption {
        type = types.str;
        description =
          "A short description of the service. Placed as a comment in the script for debugging.";
        default = "";
      };

      options.command = mkOption {
        type = types.nullOr types.pathInStore;
        description = "The executable to run to start this service";
        default = null;
      };

      options.commandArgs = mkOption {
        type = types.listOf types.str;
        description = "The args with which to launch `command`";
        default = [ ];
      };

      options.hasPidfile = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to automatically create a pidfile";
      };

      options.procname = mkOption {
        type = types.nullOr types.pathInStore;
        description = "The executable that must be running in order for the service to be up";
        default = null;
      };

      options.shell = mkOption {
        type = types.shellPackage;
        description =
          "The shell with which to run the rc-script when invoked directly. Probably don't change this.";
        default = pkgs.bash;
      };

      options.keywordNojail = mkOption {
        type = types.bool;
        description = "Whether this service should be disabled in jails.";
        default = false;
      };

      options.keywordNojailvnet = mkOption {
        type = types.bool;
        description =
          "Whether this service should be disabled in jails without vnets.";
        default = false;
      };

      options.keywordFirstboot = mkOption {
        type = types.bool;
        description =
          "Whether this service should only be run on the very first system boot."; # TODO is this right?
        default = false;
      };

      options.keywordNostart = mkOption {
        type = types.bool;
        description =
          "Whether this service should only not be started automatically on boot.";
        default = false;
      };

      options.keywordSuspend = mkOption {
        type = types.bool;
        description =
          "Whether this service should be stopped on system suspend."; # TODO is this right?
        default = false;
      };

      options.keywordResume = mkOption {
        type = types.bool;
        description =
          "Whether this service should be started on resume from suspend."; # TODO is this right?
        default = false;
      };

      options.keywordShutdown = mkOption {
        type = types.bool;
        description =
          "Whether this service should be automatically stopped at system shutdown.";
        default = false;
      };

      options.keywordUser = mkOption {
        type = types.bool;
        description =
          "Whether this service should be run iff a user is starting a session.";
        default = false;
      };

      options.requires = mkOption {
        type = types.listOf types.str;
        description =
          "The services or phases that must be started before this service starts.";
        default = [ ];
      };

      options.before = mkOption {
        type = types.listOf types.str;
        description =
          "The services or phases before which this service must be started.";
        default = [ ];
      };

      options.keywords = mkOption {
        type = types.listOf types.str;
        description =
          "The service keywords, used for filtering based on well-known service considerations.";
        default = [ ];
      };

      config.keywords = [ ] ++ optionals config.keywordShutdown [ "shutdown" ]
        ++ optionals config.keywordNojail [ "nojail" ]
        ++ optionals config.keywordNojailvnet [ "nojailvnet" ]
        ++ optionals config.keywordFirstboot [ "firstboot" ]
        ++ optionals config.keywordNostart [ "nostart" ]
        ++ optionals config.keywordSuspend [ "suspend" ]
        ++ optionals config.keywordResume [ "resume" ]
        ++ optionals config.keywordUser [ "user" ];

      options.commands = mkOption {
        type = types.attrsOf (types.nullOr types.str);
        description = "A mapping from command name to command text.";
        default = { };
      };

      options.precmds = mkOption {
        type = types.attrsOf types.str;
        description = "A mapping from command name to precommand text.";
        default = { };
      };

      options.postcmds = mkOption {
        type = types.attrsOf types.str;
        description = "A mapping from command name to postcommand text.";
        default = { };
      };

      options.extraConfig = mkOption {
        type = types.lines;
        description =
          "Extra configuration to add just before the end of the rc script.";
        default = "";
      };

      options.binDeps = mkOption {
        type = types.listOf types.package;
        description =
          "Any packages whose bin directories should be made available during command execution.";
        default = [ pkgs.coreutils pkgs.freebsd.bin pkgs.freebsd.limits ];
      };

      options.defaultBinDeps = mkOption {
        type = types.listOf types.package;
        description =
          "Packages to be added after binDeps, generally includes coreutils and freebsd bins";
        default = [ pkgs.coreutils pkgs.freebsd.bin pkgs.freebsd.limits ];
      };

      options.environment = mkOption {
        type = with types; attrsOf (nullOr (oneOf [ str path package ]));
        default = { };
        example = { CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"; };
        description =
          "Extra environment variables to set during command execution";
      };

      options.dummy = mkOption {
        type = types.bool;
        description =
          "Whether this is a dummy script, i.e. a stage ordering marker.";
        default = false;
      };
    }));
  };

  options.rc.conf = mkOption {
    type = types.attrsOf (types.either types.str types.bool);
    description = "Key-value pairs that should be set in rc.conf";
    default = { };
  };

  options.rc.rootRwMount = mkOption {
    type = types.bool;
    description = "Set to false to inhibit remounting root read-write";
    default = true;
  };

  options.rc.bootInfo = mkOption {
    type = types.bool;
    description = "Enables display of informational messages at boot";
    default = false;
  };

  options.rc.startMsgs = mkOption {
    type = types.bool;
    description = ''Show "Starting foo:" messages at boot'';
    default = true;
  };

  config = mkIf cfg.enabled {
    rc.conf = {
      root_rw_mount = cfg.rootRwMount;
      rc_startmsgs = cfg.startMsgs;
      rc_info = cfg.bootInfo;
    } // (mapAttrs' (_: val:
      nameValuePair ((if (builtins.isString val.provides) then
        val.provides
      else
        builtins.elemAt val.provides 0) + "_enable") "YES") cfg.services);
    environment.etc."rc" = {
      source = "${cfg.package}/etc/*";
      target = ".";
    };
    environment.etc."rc.d".source = mkRcDir (attrValues cfg.services);
    environment.etc."rc.conf".source = mkRcConf cfg.conf;
  };
}
