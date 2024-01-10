{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.newsyslog;

  compressionFlags = {
    none = "";
    bzip2 = "J";
    xz = "X";
    zstd = "Y";
    gzip = "Z";
  };
  compressionType = types.enum (attrNames compressionFlags);
  logfileSubmodule = { name, config, ... }: {
    options = {
      path = mkOption {
        type = types.path;
        default = name;
        description = lib.mdDoc ''
          Path to the file to create. If it already exists it may be rotated.
        '';
      };
      owner = mkOption {
        type = with types; nullOr (either str int);
        default = null;
        description = lib.mdDoc ''
          Owner of archived files, either a username or a uid.
        '';
      };
      group = mkOption {
        type = with types; nullOr (either str int);
        default = null;
        description = lib.mdDoc ''
          Owning group of archived files, either a group name or a gid.
        '';
      };
      mode = mkOption {
        type = types.strMatching "0?[0-7]{3}";
        default = "600";
        description = lib.mdDoc ''
          File mode for the log and archive files, in octal.
          Execute permissions will be ignored.
        '';
      };
      count = mkOption {
        type = types.ints.unsigned;
        default = 7;
        description = lib.mdDoc ''
          Maximum number of archived log files at a time.
          This does not include the currently active file.
        '';
      };
      size = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = lib.mdDoc ''
          Maximum size of an archived log file, in KiB
        '';
      };
      when = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = lib.mdDoc ''
          When to rotate log files, regardless of size.
          For format see {manpage}`newsyslog.conf(5)`
        '';
      };
      pidFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = lib.mdDoc ''
          Path to pidfile of process to signal. If `pidFile`, `pidGroupFile`, and `commandFile` are all `null`,
          then a signal is sent to `syslogd`.
        '';
      };
      pidGroupFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = lib.mdDoc ''
          Path to pidfile of process group to signal. If `pidFile`, `pidGroupFile`, and `commandFile` are all `null`,
          then a signal is sent to `syslogd`.
        '';
      };
      commandFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = lib.mdDoc ''
          Path to a process to call when file is rotated.
          If `pidFile`, `pidGroupFile`, and `commandFile` are all `null`,
          then a signal is sent to `syslogd`.
        '';
      };
      signal = mkOption {
        type = types.str;
        default = "SIGHUP";
        description = lib.mdDoc ''
          Signal to send when file is rotated.
        '';
      };
      flags.binary = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          The file is binary, meaning don't insert a rotation message.
        '';
      };
      flags.create = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Create the log file if it does not exist.
        '';
      };
      flags.compression = mkOption {
        type = compressionType;
        default = cfg.defaultCompression;
        description = lib.mdDoc ''
          Method used to compress archived files.
        '';
      };
      flags.noDump = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Mark the file as UF_NODUMP, so it may not be backed up.
        '';
      };
      flags.noEmptyRotate = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Don't rotate the log file if empty.
        '';
      };
      flags.isGlob = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Marks path as a glob.
        '';
      };
      flags.noSignal = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Don't signal the calling process
        '';
      };
      flags.noCompressFirst = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Don't compress the 0th archived file.
        '';
      };
      flags.alternateMessage = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Use an RFC5424 rotation message instead of RFC3164.
        '';
      };
    };
  };

  formatFlags = cfg:
    with cfg.flags;
    let
      origFlags = optionalString binary "B" + optionalString create "C"
        + optionalString noDump "D" + optionalString noEmptyRotate "E"
        + optionalString isGlob "G" + optionalString noSignal "N"
        + optionalString noCompressFirst "P"
        + optionalString alternateMessage "T" + compressionFlags.${compression}
        + (if cfg.pidGroupFile != null then
          "U"
        else if cfg.commandFile != null then
          "R"
        else
          "");
    in if origFlags == "" then "-" else origFlags;

  formatOwner = cfg:
    let
      owner = if cfg.owner == null then "" else cfg.owner;
      group = if cfg.group == null then "" else cfg.group;
    in if owner == "" && group == "" then "" else "${owner}:${group}";

  formatLine = cfg:
    let
      owner = formatOwner cfg;
      flags = formatFlags cfg;
      when = if cfg.when == null then "*" else cfg.when;
      size = if cfg.size == null then "*" else cfg.size;
      signal = if cfg.signal == "SIGHUP" then "" else cfg.signal;
      pidCmdFile = if cfg.pidFile != null then
        cfg.pidFile
      else if cfg.pidGroupFile != null then
        cfg.pidGroupFile
      else if cfg.commandFile != null then
        cfg.commandFile
      else
        "";
    in "${cfg.path} ${owner} ${cfg.mode} ${
      toString cfg.count
    } ${size} ${when} ${flags} ${pidCmdFile} ${signal}";

  configFile = pkgs.writeText "newsyslog.conf"
    (concatMapStringsSep "\n" formatLine (attrValues cfg.logfiles));
in {
  options.services.newsyslog = {
    package = mkPackageOption pkgs [ "freebsd" "newsyslog" ] { };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "-a" "/var/log/archive" ];
      description = lib.mdDoc ''
        Extra arguments to call `newsyslog` with.
      '';
    };

    defaultCompression = mkOption {
      type = compressionType;
      default = "bzip2";
      example = "zstd";
      description = lib.mdDoc ''
        Compression to use for logfiles when no other is specified.
      '';
    };

    createDefault = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = lib.mdDoc ''
        Create files specified in syslogd by default.
      '';
    };

    logfiles = mkOption {
      type = types.attrsOf (types.submodule logfileSubmodule);
      default = { };
      description = lib.mdDoc ''
        List of logfiles to create and rotate. These are primarily used for syslogd,
        but can also be used for other daemons like ftp.
      '';
    };
  };

  config = {
    rc.services.newsyslog = {
      description = "Logfile rotation";
      provides = "newsyslog";
      requires = [ "FILESYSTEMS" "tempfiles" ];
      command = "${cfg.package}/bin/newsyslog";
      commandArgs = [ "-C" "-f" (toString configFile) ] ++ cfg.extraArgs;
      commands.stop = ":";
    };

    services.newsyslog.logfiles = mkIf cfg.createDefault (mapAttrs (name: value:
      mkDefault {
        path = value.destination;
        flags.create = hasPrefix "/var/log/" value.destination;
      }) config.services.syslogd.fileActions);
  };
}
