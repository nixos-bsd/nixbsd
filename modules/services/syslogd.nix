{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.syslogd;

  selectorSubmodule = { config, ... }: {
    options = {
      facility = mkOption {
        type = types.nullOr (types.enum [
          "auth"
          "authpriv"
          "console"
          "cron"
          "daemon"
          "ftp"
          "kern"
          "lpr"
          "mail"
          "mark"
          "news"
          "ntp"
          "security"
          "syslog"
          "user"
          "uucp"
          "local0"
          "local1"
          "local2"
          "local3"
          "local4"
          "local5"
          "local6"
          "local7"
        ]);
        default = null;
      };
      comparisonFlag = mkOption {
        type = types.strMatching "!?[<=>]+";
        default = ">=";
        description = lib.mdDoc ''
          How to compare the message's level with the rule's level.
          Default is >=, meaning all messages with a level greater or
          equal to specified will be matched;
        '';
      };
      level = mkOption {
        type = types.nullOr (types.enum [
          "emerg"
          "alert"
          "crit"
          "err"
          "warning"
          "notice"
          "info"
          "debug"
          "none"
        ]);
        default = null;
        description = lib.mdDoc ''
          Message severity to compare against with compareFlag.
          If this is null then all messages will be matched and compareFlag will be ignored.
        '';
      };
      text = mkOption {
        type = types.str;
        example = "*.emerg";
        description = lib.mdDoc ''
          Full text of selector.
        '';
      };
    };
    config = {
      text = let
        facility = if config.facility == null then "*" else config.facility;
        comparisonFlag =
          if config.comparisonFlag == ">=" then "" else config.comparisonFlag;
        level = if config.level == null then "*" else config.level;
      in mkDefault "${facility}.${comparisonFlag}${level}";
    };
  };

  formatAction = config: actionText:
    let
      selectors = concatMapStringsSep ";" (sel: sel.text) config.selectors;
      programFilter = if config.includedPrograms != [ ] then
        "!" + concatStringsSep "," config.includedPrograms
      else if config.excludedPrograms != [ ] then
        "!-" + concatStringsSep "," config.excludedPrograms
      else
        "";
      hostFilter = if config.includedHosts != [ ] then
        "+" + concatStringsSep "," config.includedHosts
      else if config.excludedHosts != [ ] then
        "-" + concatStringsSep "," config.excludedHosts
      else
        "";
      propertyFilter =
        if config.propertyFilter != null then config.propertyFilter else "";
      resetProgramFilter = if programFilter == "" then "" else "!*";
      resetHostFilter = if hostFilter == "" then "" else "+*";
      resetPropertyFilter = if propertyFilter == "" then "" else ":*";
    in ''
      ${programFilter}
      ${hostFilter}
      ${propertyFilter}
      ${selectors} ${actionText}
      ${resetProgramFilter}
      ${resetHostFilter}
      ${resetPropertyFilter}
    '';

  commonActionOptions = {
    selectors = mkOption {
      type = types.nonEmptyListOf (types.submodule selectorSubmodule);
      default = [ { } ];
      description = lib.mdDoc ''
        Facility/level selectors to match.
      '';
    };
    # TODO: @artemist add assertions that these are mutually exclusive
    includedPrograms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = lib.mdDoc ''
        Executables names to match.
      '';
    };

    excludedPrograms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = lib.mdDoc ''
        Executables to ignore.
      '';
    };

    includedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = lib.mdDoc ''
        Hostnames to match.
        The special value `@` means only the current host.
      '';
    };

    excludedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = lib.mdDoc ''
        Hostnames to ignore.
      '';
    };

    propertyFilter = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = lib.mdDoc ''
        The "property-based" filter to apply to the rule.
        For syntax see {manpage}`syslog.conf(5)`.
      '';
    };

    text = mkOption {
      type = types.str;
      description = lib.mdDoc ''
        Full text of a rule. This should revert any state changes it makes,
        e.g. to hostname or program filter rules.
      '';
    };
  };

  fileActionSubmodule = { name, config, ... }: {
    options = commonActionOptions // {
      destination = mkOption {
        type = types.path;
        default = name;
        example = "/var/log/messages";
        description = lib.mdDoc ''
          Destination file for matched logs.
        '';
      };
      sync = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = lib.mdDoc ''
          Whether to sync after writing new messages.
          Disabling this could increase performance but cause data loss.
        '';
      };
    };
    config = {
      text = let sync = if config.sync then "" else "-";
      in mkDefault (formatAction config "${sync}${config.destination}");
    };
  };
  userActionSubmodule = { name, config, ... }: {
    options = commonActionOptions // {
      destinations = mkOption {
        type = types.listOf types.str;
        default = [ name ];
        example = [ ];
        description = lib.mdDoc ''
          Users to send messages to.
          Empty means "all logged in users".
        '';
      };
    };
    config = {
      text = let
        users = if config.destinations == [ ] then
          "*"
        else
          concatStringsSep "," config.destinations;
      in mkDefault (formatAction config users);
    };
  };
  remoteActionSubmodule = { name, config, ... }: {
    options = commonActionOptions // {
      destination = mkOption {
        type = types.str;
        default = name;
        example = "[2001:db8::1234]:8514";
        description = lib.mdDoc ''
          Destination syslogd to send messages.
          Can be an IPv4 address, IPv6 address in brackets, or hostname,
          plus an optional port after a colon.
        '';
      };
    };
    config = {
      text = mkDefault (formatAction config "@${config.destination}");
    };
  };
  commandActionSubmodule = { name, config, ... }: {
    options = commonActionOptions // {
      command = mkOption {
        type = types.str;
        default = name;
        example = "exec /path/to/my/program.sh";
        description = lib.mdDoc ''
          Command to run when messages are recieved.
          This is run in a subshell, so exec is recommended if that is not needed.
          The command will run once the first message is recieved and recieve all
          messages on stdin.
        '';
      };
    };
    config = { text = mkDefault (formatAction config "|${config.command}"); };
  };
in {
  options = {
    services.syslogd = {
      enable = mkEnableOption "syslogd" // { default = true; };
      package = mkPackageOption pkgs [ "freebsd" "syslogd" ];
      defaultRules =
        mkEnableOption "default syslog rules, based on FreeBSD config" // {
          default = true;
        };

      extraSockets = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = lib.mdDoc ''
          Extra socket files to listen on. This is intended for jails/containers.
        '';
      };

      extraParams = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "-4" ];
        description = lib.mdDoc ''
          Extra arguments to call syslogd with.
        '';
      };

      fileActions = mkOption {
        type = types.attrsOf (types.submodule fileActionSubmodule);
        default = { };
        description = lib.mdDoc ''
          Actions outputting to a file.
        '';
      };
      userActions = mkOption {
        type = types.attrsOf (types.submodule userActionSubmodule);
        default = { };
        description = lib.mdDoc ''
          Actions outputting to a user's console.
        '';
      };
      remoteActions = mkOption {
        type = types.attrsOf (types.submodule remoteActionSubmodule);
        default = { };
        description = lib.mdDoc ''
          Actions that send to a remote syslogd.
        '';
      };
      commandActions = mkOption {
        type = types.attrsOf (types.submodule commandActionSubmodule);
        default = { };
        description = lib.mdDoc ''
          Actions that run a command filter.
        '';
      };
    };
  };
  config = mkIf cfg.enable {
    services.syslogd.fileActions = mkIf cfg.defaultRules {
      "/dev/console".selectors = [
        { level = "err"; }
        {
          facility = "kern";
          level = "warning";
        }
        {
          facility = "auth";
          level = "notice";
        }
        {
          facility = "mail";
          level = "crit";
        }
      ];
      "/var/log/messages".selectors = [
        { level = "notice"; }
        {
          facility = "authpriv";
          level = "none";
        }
        {
          facility = "kern";
          level = "debug";
        }
        {
          facility = "lpr";
          level = "info";
        }
        {
          facility = "mail";
          level = "crit";
        }
        {
          facility = "news";
          level = "err";
        }
      ];
      "/var/log/security".selectors = [{ facility = "security"; }];
      "/var/log/auth.log".selectors = [
        {
          facility = "auth";
          level = "info";
        }
        {
          facility = "authpriv";
          level = "info";
        }
      ];
      "/var/log/maillog".selectors = [{
        facility = "mail";
        level = "info";
      }];
      "/var/log/cron".selectors = [{ facility = "cron"; }];
      "/var/log/debug.log" = {
        excludedPrograms = [ "devd" ];
        selectors = [{
          comparisonFlag = "=";
          level = "debug";
        }];
      };
      "/var/log/daemon.log" = {
        excludedPrograms = [ "devd" ];
        selectors = [{
          facility = "daemon";
          level = "info";
        }];
      };
    };
    services.syslogd.userActions =
      mkIf cfg.defaultRules { "*".selectors = [{ level = "emerg"; }]; };

    # We need a file in etc for reload
    environment.etc."syslog.conf".text = let
      formatActions = actions:
        concatMapStringsSep "\n" (action: action.text) (attrValues actions);
    in ''
      ${formatActions cfg.fileActions}
      ${formatActions cfg.userActions}
      ${formatActions cfg.remoteActions}
      ${formatActions cfg.commandActions}
    '';
  };
}

