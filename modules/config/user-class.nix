{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cap_mkdb =
    {
      freebsd = lib.getExe pkgs.freebsd.cap_mkdb;
      openbsd = lib.getExe pkgs.openbsd.cap_mkdb;
    }
    .${pkgs.stdenv.hostPlatform.parsed.kernel.name};

  time = types.strMatching "inf(inity)?|unlimit(ed)?|([0-9]+[ywdhms])+";
  size = types.strMatching "inf(inity)?|unlimit(ed)?|([0-9]+[bBkKmMgGtT])+";
  number = types.either types.ints.positive (
    types.enum [
      "inf"
      "infinity"
      "unlimit"
      "unlimited"
    ]
  );
  limit =
    baseType:
    with types;
    either baseType (submodule {
      options = {
        cur = mkOption {
          type = baseType;
          description = ''
            Maximum value at start
          '';
        };
        max = mkOption {
          type = baseType;
          description = ''
            Maximum value user is allowed to set
          '';
        };
      };
    });

  # More characters are representable, but

  escapeString =
    builtins.replaceStrings
      [ "\\" ":" "^" "\t" "\n" ]
      [ "\\\\" "\\c" "\\^" "\\t" "\\n" ];

  formatField =
    name: value:
    if
      elem value [
        null
        false
      ]
    then
      [ ]
    else if value == true then
      [ name ]
    else if
      elem (builtins.typeOf value) [
        "int"
        "path"
        "string"
      ]
    then
      [ "${name}=${escapeString (toString value)}" ]
    else if builtins.typeOf value == "set" && value ? cur && value ? max then
      [
        "${name}-cur=${value.cur}"
        "${name}-max=${value.max}"
      ]
    else
      throw "Invalid value for users.classes.<name>.${name}";

  formatLine =
    _: cfg:
    let
      nameField = (concatStringsSep "|" cfg.names);
      filtered = removeAttrs cfg.settings [ "_module" ];
    in
    concatStringsSep ":" ([ nameField ] ++ concatLists (mapAttrsToList formatField filtered));

  classOpts =
    { name, config, ... }:
    {
      options = {
        names = mkOption {
          type = types.listOf types.str;
          description = ''
            Names of this user class
          '';
        };

        settings = mkOption {
          default = { };
          description = "Settings for user class";
          type = types.submodule {
            freeformType =
              with types;
              attrsOf (
                nullOr (oneOf [
                  int
                  path
                  str
                  bool
                ])
              );
            options = {
              # Resource Limits
              coredumpsize = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum coredump size limit
                '';
              };
              cputime = mkOption {
                type = limit time;
                default = "unlimited";
                description = ''
                  CPU usage limit
                '';
              };
              datasize = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum data size limit
                '';
              };
              filesize = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum file size limit
                '';
              };
              maxproc = mkOption {
                type = limit number;
                default = "unlimited";
                description = ''
                  Maximum number of processes
                '';
              };
              memorylocked = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum locked in core memory size limit
                '';
              };
              memoryuse = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum of core memory use size limit
                '';
              };
              openfiles = mkOption {
                type = limit number;
                default = "unlimited";
                description = ''
                  Maximum number of open files per process
                '';
              };
              sbsize = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum permitted socketbuffer size
                '';
              };
              vmemoryuse = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum permitted total VM usage per process
                '';
              };
              stacksize = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum stack size limit
                '';
              };
              pseudoterminals = mkOption {
                type = limit number;
                default = "unlimited";
                description = ''
                  Maximum number of pseudoterminals
                '';
              };
              swapuse = mkOption {
                type = limit size;
                default = "unlimited";
                description = ''
                  Maximum swap space size limit
                '';
              };
              umtxp = mkOption {
                type = limit number;
                default = "unlimited";
                description = ''
                  Maximum number of process-shared pthread locks
                '';
              };

              # Environment
              charset = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  MIME character set used by applications
                '';
              };
              cpumask = mkOption {
                type = types.strMatching "default|all|[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*";
                default = "default";
                description = ''
                  List of cpus to bind the user to
                '';
              };
              hushlogin = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Disable the login banner
                '';
              };
              ignorenologin = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Login not prevented by nologin
                '';
              };
              ftp-chroot = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Limit FTP access with chroot to the user home directory
                '';
              };
              label = mkOption {
                # TODO: validate this more, see `man 7 maclabel`
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Default MAC (Manditory Access Control) policy
                '';
              };
              lang = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Language, sets LANG environment variable
                '';
              };
              mail = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Sets MAIL environment variable
                '';
              };
              manpath = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Default search path for manpages
                '';
              };
              nocheckmail = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Don't display mail status at login
                '';
              };
              nologin = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = ''
                  If the file exists it will be displayed and the login session will
                  be terminated
                '';
              };
              path = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Default search path
                '';
              };
              priority = mkOption {
                type = types.nullOr (types.ints.between (-20) 20);
                default = null;
                description = ''
                  Initial nice level
                '';
              };
              requirehome = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Require a valid home directory to login
                '';
              };
            };
          };
        };
      };

      config = {
        names = lib.mkDefault [ name ];
      };
    };
in
{
  options = {
    users.classes = mkOption {
      default = {
        default = { };
        root = { };
        daemon = { };
      };
      type = types.attrsOf (types.submodule classOpts);
      description = ''
        User classes, as seen in /etc/login.conf
      '';
    };
  };

  config = {
    environment.etc."login.conf" = {
      mode = "0644";
      uid = 0;
      gid = 0;
      text = concatStringsSep "\n" (lib.mapAttrsToList formatLine config.users.classes);
    };

    system.activationScripts.cap_mkdb = {
      deps = [ "etc" ];
      text = ''
        ${cap_mkdb} /etc/login.conf
      '';
    };
  };
}
