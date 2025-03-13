{ config, pkgs, lib, ... }:
let
  cfg = config.services.fcron;

  queuelen = lib.optionals (cfg.queuelen != null) ["-q" (toString cfg.queuelen)];

  # Duplicate code, also found in cron.nix. Needs deduplication.
  fcrontab = ''
    SHELL=${pkgs.bash}/bin/bash
    PATH=${config.system.path}/bin:${config.system.path}/sbin
    ${lib.optionalString (cfg.mailto != null) ''
      MAILTO="${cfg.mailto}"
    ''}
    NIX_CONF_DIR=/etc/nix
    ${lib.concatStrings (map (job: "# ${job.name}\n${lib.optionalString (job.description != "") "# ${job.description}\n"}${job.line}\n") (lib.attrValues cfg.jobs))}
  '';

  allowdeny = target: users: {
    source = pkgs.writeText "fcron.${target}" (lib.concatStringsSep "\n" users);
    target = "fcron.${target}";
    mode = "644";
    gid = config.ids.gids.fcron;
  };
in
{
  options.services.fcron = {
    enable = lib.mkEnableOption "fcron" // { default = true; };

    allow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "all" ];
      description = ''
        Users allowed to use fcrontab and fcrondyn (one name per
        line, `all` for everyone).
      '';
    };

    deny = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users forbidden from using fcron.";
    };

    mailto = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email address to which job output will be mailed.";
    };

    maxSerialJobs = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Maximum number of serial jobs which can run simultaneously.";
    };

    queuelen = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Number of jobs the serial queue and the lavg queue can contain.";
    };

    jobs = lib.mkOption {
      default = { };
      description = "Jobs to execute.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Name of the job.";
              };

              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Description of the job.";
              };

              line = lib.mkOption {
                type = lib.types.str;
                description = "The fcrontab line defining this job.";
              };

              when.elapsed = lib.mkOption {
                description = "Time period in which each repetition should trigger the command.";
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "2d";
              };
              when.clock = lib.mkOption {
                description = "Time unit constraints which must be satisfied to trigger the command.";
                default = null;
                type = lib.types.nullOr (lib.types.submodule (
                  { ... }:
                  let
                    mkClockOption = {
                      longname,
                      min,
                      max,
                      keywords ? [],
                      }:
                      let
                        basicTypes = [(lib.types.ints.between min max)]
                          ++ lib.optional ((builtins.length keywords) != 0) (lib.types.enum keywords);
                        rangeType = (lib.types.submodule ({ ... }: {
                          options.min = lib.mkOption {
                            type = lib.types.oneOf basicTypes;
                          };
                          options.max = lib.mkOption {
                            type = lib.types.oneOf basicTypes;
                          };
                          options.interval = lib.mkOption {
                            type = lib.types.nullOr (lib.types.oneOf basicTypes);
                            default = null;
                          };
                          options.except = lib.mkOption {
                            type = lib.types.either (lib.types.oneOf basicTypes) (lib.types.listOf (lib.types.oneOf basicTypes));
                            default = [];
                          };
                        }));
                      in lib.mkOption {
                      description = "The command should be executed every <value> ${longname}";
                      example = {
                            min = 1;
                            max = 5;
                            interval = 2;
                            except = 3;
                      };
                      default = null;
                        type = lib.types.nullOr (lib.types.oneOf (basicTypes ++ [
                        (lib.types.listOf (lib.types.oneOf basicTypes))
                        rangeType
                        (lib.types.listOf rangeType)
                      ]));
                    };
                  in
                  {
                    options = {
                      text = lib.mkOption {
                        description = "Line of the following form: min hrs day-of-month month day-of-week, in which all conditions must be met to trigger the command.";
                        type = lib.types.nullOr lib.types.str;
                        example = "5 10 31 * 7";
                      };
                      min = mkClockOption {
                        longname = "minutes";
                        min = 0;
                        max = 59;
                      };
                      hr = mkClockOption {
                        longname = "hours";
                        min = 0;
                        max = 23;
                      };
                      dayOfMonth = mkClockOption {
                        longname = "days of the month";
                        min = 1;
                        max = 31;
                      };
                      month = mkClockOption {
                        longname = "months";
                        min = 1;
                        max = 12;
                        keywords = [ "jan" "feb" "mar" "apr" "may" "jun" "jul" "aug" "sep" "oct" "nov" "dec" ];
                      };
                      dayOfWeek = mkClockOption {
                        longname = "days of the week";
                        min = 0;
                        max = 7;
                        keywords = [ "mon" "tue" "wed" "thu" "fri" "sat" "sun" ];
                      };
                    };
                    config = lib.mkIf (config.min != null || config.hr != null || config.dayOfMonth != null || config.month != null || config.dayOfWeek != null) {
                      text = let
                        processPrim = builtins.toString;
                        processInterval = val: if val == null then "" else "/${processPrim val}";
                        processExcept = val: if builtins.isList val then lib.concatMapStrings processExcept val else "~${processPrim val}";
                        processRange = val: "${processPrim val.min}-${processPrim val.max}${processInterval val.interval}${processExcept val.except}";

                        processField = val: if val == null then "*"
                          else if builtins.isInt val then "${val}"
                          else if builtins.isList val then lib.concatMapStringsSep "," processField val
                          else processRange val;
                      in
                        lib.concatMapStringsSep " " processField [config.min config.hr config.dayOfMonth config.month config.dayOfWeek];
                    };
                  }
                ));
              };
              # TODO: % declarations
              #when.every = lib.mkOption {
              #};
              options = lib.mkOption {
                type = lib.types.attrsOf (lib.types.oneOf [
                  lib.types.str
                  lib.types.int
                  lib.types.bool
                ]);
                description = "Options to set on the job. See fcrontab(5) for valid options.";
                default = {};
              };
              command = lib.mkOption {
                type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
                description = "The shell command to run.";
              };
            };
            config = let
              options = lib.concatStringsSep "," (lib.mapAttrsToList (opt: val: "${opt}(${if builtins.isBool val then (if val then "true" else "false") else builtins.toString val})") config.options);
              command = if builtins.isList config.command then lib.escapeShellArgs config.command else config.command;
            in lib.mkMerge [ (lib.mkIf (config.when.elapsed != null) {
              line = "@${options} ${config.when.elapsed} ${command}";
            }) (lib.mkIf (config.when.clock != null) {
              line = "&${options} ${config.when.clock.line} ${command}";
            }) {
              name = lib.mkOptionDefault name;
            }];
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = lib.listToAttrs (
      map
        (x: {
          name = x.target;
          value = x;
        })
        [
          (allowdeny "allow" (cfg.allow))
          (allowdeny "deny" cfg.deny)
          # see man 5 fcron.conf
          {
            source =
              let
                isSendmailWrapped = lib.hasAttr "sendmail" config.security.wrappers;
                sendmailPath =
                  if isSendmailWrapped then "/run/wrappers/bin/sendmail" else "${config.system.path}/bin/sendmail";
              in
              pkgs.writeText "fcron.conf" ''
                fcrontabs   =       /var/spool/fcron
                pidfile     =       /run/fcron.pid
                fifofile    =       /run/fcron.fifo
                fcronallow  =       /etc/fcron.allow
                fcrondeny   =       /etc/fcron.deny
                shell       =       /bin/sh
                sendmail    =       ${sendmailPath}
                editor      =       ${pkgs.vim}/bin/vim
              '';
            target = "fcron.conf";
            gid = config.ids.gids.fcron;
            mode = "0644";
          }
        ]
    );

    environment.systemPackages = [ pkgs.fcron ];
    users.users.fcron = {
      uid = config.ids.uids.fcron;
      home = "/var/spool/fcron";
      group = "fcron";
    };
    users.groups.fcron.gid = config.ids.gids.fcron;

    security.wrappers = {
      fcrontab = {
        source = "${pkgs.fcron}/bin/fcrontab";
        owner = "fcron";
        group = "fcron";
        setgid = true;
        setuid = true;
      };
      fcrondyn = {
        source = "${pkgs.fcron}/bin/fcrondyn";
        owner = "fcron";
        group = "fcron";
        setgid = true;
        setuid = false;
      };
      fcronsighup = {
        source = "${pkgs.fcron}/bin/fcronsighup";
        owner = "root";
        group = "fcron";
        setuid = true;
      };
    };

    systemd.tmpfiles.settings.fcron."/var/spool/fcron".d = {
      mode = "0770";
      user = "fcron";
      group = "fcron";
    };

    init.services.fcron = {
      description = "fcron timed job scheduling daemon";
      dependencies = [ "DAEMON" ];

      path = [ pkgs.fcron ];

      preStart = ''
        # load system crontab file
        /run/wrappers/bin/fcrontab -u systab - < ${pkgs.writeText "fcrontab" fcrontab}
      '';

      startType = "forking";
      startCommand = [ "${pkgs.fcron}/sbin/fcron" "-m" (toString cfg.maxSerialJobs) ] ++ queuelen;
    };
  };
}
