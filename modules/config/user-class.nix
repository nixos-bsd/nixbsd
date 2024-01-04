{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.users.classes;

  time = types.strMatching "inf(inity)?|unlimit(ed)?|([0-9]+[ywdhms])+";
  size = types.strMatching "inf(inity)?|unlimit(ed)?|([0-9]+[bBkKmMgGtT])+";
  number = types.either types.ints.positive
    (types.enum [ "inf" "infinity" "unlimit" "unlimited" ]);
  limit = baseType:
    with types;
    either baseType (submodule {
      options = {
        cur = mkOption {
          type = baseType;
          description = lib.mdDoc ''
            Maximum value at start
          '';
        };
        max = mkOption {
          type = baseType;
          description = lib.mdDoc ''
            Maximum value user is allowed to set
          '';
        };
      };
    });

  classOpts = { name, config, ... }: {
    options = {
      names = mkOption {
        type = types.listOf types.str;
        default = [ name ];
        description = lib.mdDoc ''
          Names of this user class
        '';
      };
      text = mkOption {
        type = types.str;
        internal = true;
        description = lib.mdDoc ''
          Text of the line in login.conf
        '';
      };

      # Resource Limits
      coredumpsize = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum coredump size limit
        '';
      };
      cputime = mkOption {
        type = limit time;
        default = "unlimited";
        description = lib.mdDoc ''
          CPU usage limit
        '';
      };
      datasize = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum data size limit
        '';
      };
      filesize = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum file size limit
        '';
      };
      maxproc = mkOption {
        type = limit number;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum number of processes
        '';
      };
      memorylocked = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum locked in core memory size limit
        '';
      };
      memoryuse = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum of core memory use size limit
        '';
      };
      openfiles = mkOption {
        type = limit number;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum number of open files per process
        '';
      };
      sbsize = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum permitted socketbuffer size
        '';
      };
      vmemoryuse = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum permitted total VM usage per process
        '';
      };
      stacksize = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum stack size limit
        '';
      };
      pseudoterminals = mkOption {
        type = limit number;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum number of pseudoterminals
        '';
      };
      swapuse = mkOption {
        type = limit size;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum swap space size limit
        '';
      };
      umtxp = mkOption {
        type = limit number;
        default = "unlimited";
        description = lib.mdDoc ''
          Maximum number of process-shared pthread locks
        '';
      };

      # Environment
      charset = mkOption {
        type = types.nullOr types.str;
        description = lib.mdDoc ''
          MIME character set used by applications
        '';
      };
      cpumask = mkOption {
        type =
          types.strMatching "default|all|[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*";
        default = "default";
        description = lib.mdDoc ''
          List of cpus to bind the user to
        '';
      };
      hushlogin = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Disable the login banner
        '';
      };
      ignorenologin = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Login not prevented by nologin
        '';
      };
      ftp-chroot = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Limit FTP access with chroot to the user home directory
        '';
      };
      label = mkOption {
        # TODO: validate this more, see `man 7 maclabel`
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc ''
          Default MAC (Manditory Access Control) policy
        '';
      };
      lang = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc ''
          Language, sets LANG environment variable
        '';
      };
      mail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc ''
          Sets MAIL environment variable
        '';
      };
      manpath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc ''
          Default search path for manpages
        '';
      };
      nocheckmail = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Don't display mail status at login
        '';
      };
      nologin = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = lib.mdDoc ''
          If the file exists it will be displayed and the login session will
          be terminated
        '';
      };
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc ''
          Default search path
        '';
      };
      priority = mkOption {
        type = types.nullOr (types.ints.between (-20) 20);
        default = null;
        description = lib.mdDoc ''
          Initial nice level
        '';
      };
      requirehome = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Require a valid home directory to login
        '';
      };
      # TODO: add setenv, shell, term, timezone, umask, welcome
      # Authentication
      # TODO: Add fields
    };

    config = {
      charset = if config.lang == null then
        lib.mkDefault null
      else
        let parts = splitString "." config.lang;
        in lib.mkDefault (elemAt parts 1);

      text = let
        nameField = (concatStringsSep "|" config.names);
        filtered = config // {
          names = null;
          text = null;
          _module = null;
        };
        formatField = name: value:
          if elem value [ null false ] then
            [ ]
          else if value == true then
            [ name ]
          else if elem (builtins.typeOf value) [ "int" "path" "string" ] then
            [ "${name}=${toString value}" ]
          else if builtins.typeOf value == "set" && value ? cur && value
          ? max then [
            "${name}-cur=${value.cur}"
            "${name}-max=${value.max}"
          ] else
            throw "Invalid value for users.classes.<name>.${name}";
      in concatStringsSep ":"
      ([ nameField ] ++ concatLists (mapAttrsToList formatField filtered));
    };
  };
in {
  options = {
    users.classes = mkOption {
      default = {
        default = { };
        root = { };
        daemon = { };
      };
      type = types.attrsOf (types.submodule classOpts);
      description = lib.mdDoc ''
        User classes, as seen in /etc/login.conf
      '';
    };
  };

  config = {
    environment.etc."login.conf" = {
      mode = "0644";
      uid = 0;
      gid = 0;
      text =
        concatMapStringsSep "\n" (class: class.text) (builtins.attrValues cfg);
    };

    system.activationScripts.cap_mkdb = {
      deps = [ "etc" ];
      text = ''
        ${pkgs.freebsd.cap_mkdb}/bin/cap_mkdb /etc/login.conf
      '';
    };
  };
}
