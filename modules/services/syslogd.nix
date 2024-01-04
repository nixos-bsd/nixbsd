{ config, pkgs, lib, ... }:
with lib; let
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
          If this is null then all messages will be matched and compareFlag will be ignored
        '';
      };
      text = mkOption {
        type = types.str;
        example = "*.emerg";
        description = lib.mdDoc ''
          Full text of selector
        '';
      };
    };
    config = {
      text = let
        facility = if config.facility == null then "*" else config.facility;
        comparisonFlag = if config.comparisonFlag == ">=" then "" else config.comparisonFlag;
        level = if config.level == null then "*" else config.level;
      in mkDefault "${facility}.${comparisonFlag}${level}";
    };
  };

  formatAction = config: actionText: let
    selectors = concatMapStringsSep ";" (sel: sel.text) config.selectors;
    programFilter = if config.includedPrograms != [] then
      "!" + concatStringsSep "," config.includedPrograms
    else if config.excludedPrograms != [] then
      "!-" + concatStringsSep "," config.excludedPrograms
    else
      "";
    resetProgramFilter = if programFilter == "" then "" else "!*";
  in ''
    ${programFilter}
    ${selectors} ${actionText}
    ${resetProgramFilter}
  '';

  commonActionOptions = {
    selectors = mkOption {
      type = types.nonEmptyListOf (types.submodule selectorSubmodule);
      default = [ {} ];
      description = lib.mdDoc ''
        Facility/level selectors to match
      '';
    };
    # TODO: @artemist add assertions that these are mutually exclusive
    includedPrograms = mkOption {
      type = types.listOf types.str;
      default = [];
      description = lib.mdDoc ''
        Executables names to match
      '';
    };

    excludedPrograms = mkOption {
      type = types.listOf types.str;
      default = [];
      description = lib.mdDoc ''
        Executables to ignore
      '';
    };

    text = mkOption {
      type = types.str;
      description = lib.mdDoc ''
        Full text of a rule. This should revert any state changes it makes,
        e.g. to hostname or program filter rules;
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
          Destination file for matched logs
        '';
      };
      sync = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = lib.mdDoc ''
          Whether to sync after writing new messages.
          Disabling this could increase performance but cause data loss
        '';
      };
    };
    config = {
      text = let
        sync = if config.sync then "" else "-";
      in mkDefault (formatAction config "${sync}${config.destination}");
    };
  };
in {
  options = {
    services.syslogd = {
      enable = mkEnableOption "syslogd" // {
        default = true;
      };
      package = mkPackageOption pkgs [ "freebsd" "syslogd" ];
      defaultRules = mkEnableOption "default syslog rules, based on FreeBSD config" // {
        default = true;
      };
      fileActions = mkOption {
        type = types.attrsOf (types.submodule fileActionSubmodule);
        default = {};
        description = ''
          Actions outputting to a file
        '';
      };
      # TODO: @artemist: Add more action types
    };
  };
  config = mkIf cfg.enable {
    services.syslogd.fileActions = mkIf cfg.defaultRules {
      "/dev/console".selectors = [
        { level = "err"; }
        { facility = "kern"; level = "warning"; }
        { facility = "auth"; level = "notice"; }
        { facility = "mail"; level = "crit"; }
      ];
      "/var/log/messages".selectors = [
        { level = "notice"; }
        { facility = "authpriv"; level = "none"; }
        { facility = "kern"; level = "debug"; }
        { facility = "lpr"; level = "info"; }
        { facility = "mail"; level = "crit"; }
        { facility = "news"; level = "err"; }
      ];
      "/var/log/security".selectors = [
        { facility = "security"; }
      ];
      "/var/log/auth.log".selectors = [
        { facility = "auth"; level = "info"; }
        { facility = "authpriv"; level = "info"; }
      ];
      "/var/log/maillog".selectors = [
        { facility = "mail"; level = "info"; }
      ];
      "/var/log/cron".selectors = [
        { facility = "cron"; }
      ];
      "/var/log/debug.log" = {
        excludedPrograms = [ "devd" ];
        selectors = [
          { comparisonFlag = "="; level = "debug"; }
        ];
      };
      "/var/log/daemon.log" = {
        excludedPrograms = [ "devd" ];
        selectors = [
          { facility = "daemon"; level = "info"; }
        ];
      };
    };

    environment.etc."syslog.conf".text = let
      formatActions = actions: concatMapStringsSep "\n" (action: action.text) (attrValues actions);
    in ''
      ${formatActions cfg.fileActions}
    '';
  };
}


