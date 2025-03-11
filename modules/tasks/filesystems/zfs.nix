{ config, lib, options, pkgs, utils, ... }:
#
# TODO: zfs tunables

let

  cfgZfs = config.boot.zfs;
  cfgZfsd = config.services.zfsd;
  cfgExpandOnBoot = config.services.zfs.expandOnBoot;
  cfgSnapshots = config.services.zfs.autoSnapshot;
  cfgSnapFlags = cfgSnapshots.flags;
  cfgScrub = config.services.zfs.autoScrub;
  cfgTrim = config.services.zfs.trim;

  inInitrd = config.boot.initrd.supportedFilesystems.zfs or false;
  inSystem = config.boot.supportedFilesystems.zfs or false;

  autosnapPkg = pkgs.zfstools.override {
    zfs = cfgZfs.package;
  };

  zfsAutoSnap = "${autosnapPkg}/bin/zfs-auto-snapshot";

  datasetToPool = x: lib.elemAt (lib.splitString "/" x) 0;

  fsToPool = fs: datasetToPool fs.device;

  zfsFilesystems = lib.filter (x: x.fsType == "zfs") config.system.build.fileSystems;

  allPools = lib.unique ((map fsToPool zfsFilesystems) ++ cfgZfs.extraPools);

  rootPools = lib.unique (map fsToPool (lib.filter utils.fsNeededForBoot zfsFilesystems));

  dataPools = lib.unique (lib.filter (pool: !(lib.elem pool rootPools)) allPools);

  snapshotNames = [ "frequent" "hourly" "daily" "weekly" "monthly" ];

  # When importing ZFS pools, there's one difficulty: These scripts may run
  # before the backing devices (physical HDDs, etc.) of the pool have been
  # scanned and initialized.
  #
  # An attempted import with all devices missing will just fail, and can be
  # retried, but an import where e.g. two out of three disks in a three-way
  # mirror are missing, will succeed. This is a problem: When the missing disks
  # are later discovered, they won't be automatically set online, rendering the
  # pool redundancy-less (and far slower) until such time as the system reboots.
  #
  # The solution is the below. poolReady checks the status of an un-imported
  # pool, to see if *every* device is available -- in which case the pool will be
  # in state ONLINE, as opposed to DEGRADED, FAULTED or MISSING.
  #
  # The import scripts then loop over this, waiting until the pool is ready or a
  # sufficient amount of time has passed that we can assume it won't be. In the
  # latter case it makes one last attempt at importing, allowing the system to
  # (eventually) boot even with a degraded pool.
  importLib = {zpoolCmd, awkCmd, pool}: let
    devNodes = if pool != null && cfgZfs.pools ? ${pool} then cfgZfs.pools.${pool}.devNodes else cfgZfs.devNodes;
    devNodes' = if devNodes == null then "" else "-d \"${devNodes}\"";
  in ''
    # shellcheck disable=SC2013
    case $(kenv zfs_force) in
      zfs_force|zfs_force=1|zfs_force=y)
        ZFS_FORCE="-f"
        ;;
    esac
    poolReady() {
      pool="$1"
      state="$("${zpoolCmd}" import ${devNodes'} 2>/dev/null | "${awkCmd}" "/pool: $pool/ { found = 1 }; /state:/ { if (found == 1) { print \$2; exit } }; END { if (found == 0) { print \"MISSING\" } }")"
      if [[ "$state" = "ONLINE" ]]; then
        return 0
      else
        echo "Pool $pool in state $state, waiting"
        return 1
      fi
    }
    poolImported() {
      pool="$1"
      "${zpoolCmd}" list "$pool" >/dev/null 2>/dev/null
    }
    poolImport() {
      pool="$1"
      # shellcheck disable=SC2086
      "${zpoolCmd}" import ${devNodes'} -N $ZFS_FORCE "$pool"
    }
  '';

  getPoolFilesystems = pool:
    lib.filter (x: x.fsType == "zfs" && (fsToPool x) == pool) config.system.build.fileSystems;

  getKeyLocations = pool: if lib.isBool cfgZfs.requestEncryptionCredentials then {
    hasKeys = cfgZfs.requestEncryptionCredentials;
    command = "${cfgZfs.package}/sbin/zfs list -rHo name,keylocation,keystatus -t volume,filesystem ${pool}";
  } else let
    keys = lib.filter (x: datasetToPool x == pool) cfgZfs.requestEncryptionCredentials;
  in {
    hasKeys = keys != [];
    command = "${cfgZfs.package}/sbin/zfs list -Ho name,keylocation,keystatus -t volume,filesystem ${toString keys}";
  };

  createImportService = { pool, force, prefix ? "" }:
    lib.nameValuePair "zfs-import-${pool}" {
      dependencies = [ "FILESYSTEMS" ];
      description = "Import ZFS pool \"${pool}\"";
      before = let
        poolFilesystems = getPoolFilesystems pool;
        noauto = poolFilesystems != [ ] && lib.all (fs: lib.elem "noauto" fs.options) poolFilesystems;
      in lib.optional (!noauto) "marker-zfs-import";
      startType = "oneshot";
      environment.ZFS_FORCE = lib.optionalString force "-f";
      startCommand = let
        keyLocations = getKeyLocations pool;
      in [ (pkgs.writeShellScript "zfs-import-${pool}" ((importLib {
        # See comments at importLib definition.
        zpoolCmd = "${cfgZfs.package}/sbin/zpool";
        awkCmd = "${pkgs.gawk}/bin/awk";
        inherit pool;
      }) + ''
        if ! poolImported "${pool}"; then
          echo -n "importing ZFS pool \"${pool}\"..."
          # Loop across the import until it succeeds, because the devices needed may not be discovered yet.
          for _ in $(seq 1 60); do
            poolReady "${pool}" && poolImport "${pool}" && break
            sleep 1
          done
          poolImported "${pool}" || poolImport "${pool}"  # Try one last time, e.g. to import a degraded pool.
        fi
        if poolImported "${pool}"; then
          ${lib.optionalString keyLocations.hasKeys ''
            ${keyLocations.command} | while IFS=$'\t' read -r ds kl ks; do
              {
              if [[ "$ks" != unavailable ]]; then
                continue
              fi
              case "$kl" in
                none )
                  ;;
                prompt )
                  echo 'Encrypted pools not supported right now!!'
                  ;;
                * )
                  ${cfgZfs.package}/sbin/zfs load-key "$ds"
                  ;;
              esac
              } < /dev/null # To protect while read ds kl in case anything reads stdin
            done
          ''}
          echo "Successfully imported ${pool}"
        else
          exit 1
        fi
      '')) ];
    };
in

{
  ###### interface

  options = {
    boot.zfs = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.freebsd.zfs;
        defaultText = lib.literalExpression "pkgs.freebsd.zfs";
        description = "Configured ZFS userland tools package.";
        internal = true;
      };

      enabled = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = false;
        defaultText = lib.literalMD "`true` if ZFS filesystem support is enabled";
        description = "True if ZFS filesystem support is enabled";
      };

      #allowHibernation = lib.mkOption {
      #  type = lib.types.bool;
      #  default = false;
      #  description = ''
      #    Allow hibernation support, this may be a unsafe option depending on your
      #    setup. Make sure to NOT use Swap on ZFS.
      #  '';
      #};

      extraPools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "tank" "data" ];
        description = ''
          Name or GUID of extra ZFS pools that you wish to import during boot.

          Usually this is not necessary. Instead, you should set the mountpoint property
          of ZFS filesystems to `legacy` and add the ZFS filesystems to
          NixBSD's {option}`fileSystems` option, which makes NixBSD automatically
          import the associated pool.

          However, in some cases (e.g. if you have many filesystems) it may be preferable
          to exclusively use ZFS commands to manage filesystems. If so, since NixBSD/fstab
          will not be managing those filesystems, you will need to specify the ZFS pool here
          so that NixBSD automatically imports it on every boot.
        '';
      };

      devNodes = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Name of directory from which to import ZFS device, this is passed to `zpool import`
          as the value of the `-d` option. If null, the -d option will not be passed.

          For guidance on choosing this value, see
          [the ZFS documentation](https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html#selecting-dev-names-when-creating-a-pool-linux).
        '';
      };

      forceImportRoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Forcibly import the ZFS root pool(s) during early boot.

          This is enabled by default for backwards compatibility purposes, but it is highly
          recommended to disable this option, as it bypasses some of the safeguards ZFS uses
          to protect your ZFS pools.

          If you set this option to `false` and NixBSD subsequently fails to
          boot because it cannot import the root pool, you should boot with the
          `zfs_force=1` option as a kernel environment variable (e.g. by manually
          setting a variable in stand during boot). You should only need to do this
          once.
        '';
      };

      forceImportAll = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Forcibly import all ZFS pool(s).

          If you set this option to `false` and NixBSD subsequently fails to
          import your non-root ZFS pool(s), you should manually import each pool with
          "zpool import -f \<pool-name\>", and then reboot. You should only need to do
          this once.
        '';
      };

      #requestEncryptionCredentials = lib.mkOption {
      #  type = lib.types.either lib.types.bool (lib.types.listOf lib.types.str);
      #  default = true;
      #  example = [ "tank" "data" ];
      #  description = ''
      #    If true on import encryption keys or passwords for all encrypted datasets
      #    are requested. To only decrypt selected datasets supply a list of dataset
      #    names instead. For root pools the encryption key can be supplied via both
      #    an interactive prompt (keylocation=prompt) and from a file (keylocation=file://).
      #  '';
      #};

      #passwordTimeout = lib.mkOption {
      #  type = lib.types.int;
      #  default = 0;
      #  description = ''
      #    Timeout in seconds to wait for password entry for decrypt at boot.

      #    Defaults to 0, which waits forever.
      #  '';
      #};

      pools = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            devNodes = lib.mkOption {
              type = lib.types.path;
              default = cfgZfs.devNodes;
              defaultText = "config.boot.zfs.devNodes";
              description = options.boot.zfs.devNodes.description;
            };
          };
        });
        default = { };
        description = ''
          Configuration for individual pools to override global defaults.
        '';
      };
    };

    services.zfs.autoSnapshot = {
      enable = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = ''
          Enable the (OpenSolaris-compatible) ZFS auto-snapshotting service.
          Note that you must set the `com.sun:auto-snapshot`
          property to `true` on all datasets which you wish
          to auto-snapshot.

          You can override a child dataset to use, or not use auto-snapshotting
          by setting its flag with the given interval:
          `zfs set com.sun:auto-snapshot:weekly=false DATASET`
        '';
      };

      flags = lib.mkOption {
        default = "-k -p";
        example = "-k -p --utc";
        type = lib.types.str;
        description = ''
          Flags to pass to the zfs-auto-snapshot command.

          Run `zfs-auto-snapshot` (without any arguments) to
          see available flags.

          If it's not too inconvenient for snapshots to have timestamps in UTC,
          it is suggested that you append `--utc` to the list
          of default options (see example).

          Otherwise, snapshot names can cause name conflicts or apparent time
          reversals due to daylight savings, timezone or other date/time changes.
        '';
      };

      frequent = lib.mkOption {
        default = 4;
        type = lib.types.int;
        description = ''
          Number of frequent (15-minute) auto-snapshots that you wish to keep.
        '';
      };

      hourly = lib.mkOption {
        default = 24;
        type = lib.types.int;
        description = ''
          Number of hourly auto-snapshots that you wish to keep.
        '';
      };

      daily = lib.mkOption {
        default = 7;
        type = lib.types.int;
        description = ''
          Number of daily auto-snapshots that you wish to keep.
        '';
      };

      weekly = lib.mkOption {
        default = 4;
        type = lib.types.int;
        description = ''
          Number of weekly auto-snapshots that you wish to keep.
        '';
      };

      monthly = lib.mkOption {
        default = 12;
        type = lib.types.int;
        description = ''
          Number of monthly auto-snapshots that you wish to keep.
        '';
      };
    };

    services.zfs.trim = {
      enable = lib.mkOption {
        description = "Whether to enable periodic TRIM on all ZFS pools.";
        default = true;
        example = false;
        type = lib.types.bool;
      };

      interval = lib.mkOption {
        default = "1w";
        type = lib.types.str;
        example = "1d";
        description = ''
          How often we run trim. For most desktop and server systems
          a sufficient trimming frequency is once a week.

          The format is described in
          {manpage}`fcrontab(5)`.
        '';
      };

      randomizedDelaySec = lib.mkOption {
        default = "6h";
        type = lib.types.str;
        example = "12h";
        description = ''
          Add a randomized delay before each ZFS trim.
          The delay will be chosen between zero and this value.
          This value must be a time span in the format specified by
          {manpage}`fcrontab(5)`
        '';
      };
    };

    services.zfs.autoScrub = {
      enable = lib.mkEnableOption "periodic scrubbing of ZFS pools";

      interval = lib.mkOption {
        default = "1m";
        type = lib.types.str;
        example = "2w";
        description = ''
          Systemd calendar expression when to scrub ZFS pools. See
          {manpage}`fcrontab(5)`.
        '';
      };

      # HOLY MOLY UMMM WE NEED TO PATCH FCRONTAB TO SUPPORT LONGER JITTER
      randomizedDelaySec = lib.mkOption {
        default = 255;
        type = lib.types.str;
        example = 120;
        description = ''
          Add a randomized delay in seconds before each ZFS autoscrub.
          The delay will be chosen between zero and this value.
          The value must be an integer between 0 and 255 as per the
          {manpage}`fcrontab(5)` jitter option.
        '';
      };

      pools = lib.mkOption {
        default = [];
        type = lib.types.listOf lib.types.str;
        example = [ "tank" ];
        description = ''
          List of ZFS pools to periodically scrub. If empty, all pools
          will be scrubbed.
        '';
      };
    };

    services.zfs.expandOnBoot = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "disabled" "all" ]) (lib.types.listOf lib.types.str);
      default = "disabled";
      example = [ "tank" "dozer" ];
      description = ''
        After importing, expand each device in the specified pools.

        Set the value to the plain string "all" to expand all pools on boot:

            services.zfs.expandOnBoot = "all";

        or set the value to a list of pools to expand the disks of specific pools:

            services.zfs.expandOnBoot = [ "tank" "dozer" ];
      '';
    };

    services.zfsd = {
      enable = lib.mkEnableOption "zfsd";
      package = lib.mkOption {
        description = "The package providing the zfsd binary";
        type = lib.types.package;
        default = pkgs.freebsd.zfsd;
      };
    };
  };

  ###### implementation

  config = lib.mkMerge [
    (lib.mkIf cfgZfs.enabled {
      assertions = [
        {
          assertion = config.networking.hostId != null;
          message = "ZFS requires networking.hostId to be set";
        }
        {
          assertion = !cfgZfs.forceImportAll || cfgZfs.forceImportRoot;
          message = "If you enable boot.zfs.forceImportAll, you must also enable boot.zfs.forceImportRoot";
        }
          #{
          #  assertion = cfgZfs.allowHibernation -> !cfgZfs.forceImportRoot && !cfgZfs.forceImportAll;
          #  message = "boot.zfs.allowHibernation while force importing is enabled will cause data corruption";
          #}
        {
          assertion = !(lib.elem "" allPools);
          message = ''
            Automatic pool detection found an empty pool name, which can't be used.
            Hint: for `fileSystems` entries with `fsType = zfs`, the `device` attribute
            should be a zfs dataset name, like `device = "pool/data/set"`.
            This error can be triggered by using an absolute path, such as `"/dev/disk/..."`.
          '';
        }
      ];


      boot.earlyModules = [ "zfs" ];

      #systemd.shutdownRamfs.contents."/etc/systemd/system-shutdown/zpool".source = pkgs.writeShellScript "zpool-sync-shutdown" ''
      #  exec ${cfgZfs.package}/bin/zpool sync
      #'';
      #systemd.shutdownRamfs.storePaths = ["${cfgZfs.package}/bin/zpool"];

      # ZFS already has its own scheduler. Without this my(@Artturin) computer froze for a second when I nix build something.
      #services.udev.extraRules = ''
      #  ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
      #'';

      environment.etc = {
        "zfs/zpool.d".source = "${cfgZfs.package}/etc/zfs/zpool.d/";
      };

      system.fsPackages = [ cfgZfs.package ]; # XXX: needed? zfs doesn't have (need) a fsck
      environment.systemPackages = [ cfgZfs.package ]
        ++ lib.optional cfgSnapshots.enable autosnapPkg; # so the user can run the command to see flags

      #services.udev.packages = [ cfgZfs.package ]; # to hook zvol naming, etc.

      init.services = let
        createImportService' = pool: createImportService {
          inherit pool;
          force = cfgZfs.forceImportAll;
        };

        # This forces a sync of any ZFS pools prior to poweroff, even if they're set
        # to sync=disabled.
        createSyncService = pool:
          lib.nameValuePair "zfs-sync-${pool}" {
            description = "Sync ZFS pool \"${pool}\"";
            dependencies = ["FILESYSTEMS"];
            startType = "oneshot";
            stopCommand = ''${cfgZfs.package}/bin/zfs set nixos:shutdown-time="$(date)" "${pool}"'';
            startCommand = [":"];
          };
        createMarkerService = name: lib.nameValuePair "${name}" {
          startType = "oneshot";
          dependencies = [ "FILESYSTEMS" ];
          startCommand = [":"];
        };

      in lib.listToAttrs (map createImportService' dataPools ++
          map createSyncService allPools ++
          map createMarkerService ["marker-zfs-import"]);
    })

    (lib.mkIf (cfgZfs.enabled && cfgZfsd.enable) {
      init.services.zfsd = {
        description = "The userland ZFS fault monitoring and resolution daemon";
        startCommand = [ "${cfgZfsd.package}/bin/zfsd" ];
        startType = "forking";
        dependencies = [ "FILESYSTEMS" "devd" ];
      };
    })

    (lib.mkIf (cfgZfs.enabled && cfgExpandOnBoot != "disabled") {
      init.services."zpool-expand-pools" = {
        description = "Expand ZFS pools";
        dependencies = [ "marker-zfs-import" ];

        startType = "oneshot";
        path = [ cfgZfs.package ];

        startCommand = let
          # Create a string, to be interpolated in a bash script
          # which enumerates all of the pools to expand.
          # If the `pools` option is `true`, we want to dynamically
          # expand every pool. Otherwise we want to enumerate
          # just the specifically provided list of pools.
          poolListProvider = if cfgExpandOnBoot == "all"
            then "$(zpool list -H -o name)"
            else lib.escapeShellArgs cfgExpandOnBoot;
          in [ (pkgs.writeShellScript "zpool-expand-pools" ''
          for pool in ${poolListProvider}; do
            echo "Expanding all devices for $pool."
            ${pkgs.zpool-auto-expand-partitions}/bin/zpool_part_disks --automatically-grow "$pool"
          done
        '') ];
      };
    })

    (lib.mkIf (cfgZfs.enabled && cfgSnapshots.enable) {
      services.fcron.jobs = let
        descr = name: {
          frequent = "15 mins";
          hourly = "hour";
          daily = "day";
          weekly = "week";
          monthly = "month";
        }.${name} or (throw "unknown snapshot name ${name}");
        period = name: {
          frequent = "15";
          hourly = "1h";
          daily = "1d";
          weekly = "7w";
          monthly = "1m";
        }.${name} or (throw "unknown snapshot name ${name}");
        numSnapshots = name: builtins.getAttr name cfgSnapshots;
      in builtins.listToAttrs (map (snapName:
          {
            name = "zfs-snapshot-${snapName}";
            value = {
              description = "ZFS auto-snapshotting every ${descr snapName}";
              command = "${zfsAutoSnap} ${cfgSnapFlags} ${snapName} ${toString (numSnapshots snapName)}";
              when.elapsed = period;
            };
          }) snapshotNames);
    })

    (lib.mkIf (cfgZfs.enabled && cfgScrub.enable) {
      services.fcron.jobs.zfs-scrub = {
        description = "ZFS pools scrubbing";
        command = "${cfgZfs.package}/bin/zpool scrub -w ${
            if cfgScrub.pools != [] then
              (lib.concatStringsSep " " cfgScrub.pools)
            else
              "$(${cfgZfs.package}/bin/zpool list -H -o name)"
            }";
        when.elapsed = cfgScrub.interval;
        options.jitter = cfgScrub.randomizedDelaySec;
      };
    })

    (lib.mkIf (cfgZfs.enabled && cfgTrim.enable) {
      services.fcron.jobs.zpool-trim = {
        description = "ZFS pools trim";
        when.elapsed = cfgTrim.interval;
        # By default we ignore errors returned by the trim command, in case:
        # - HDDs are mixed with SSDs
        # - There is a SSDs in a pool that is currently trimmed.
        # - There are only HDDs and we would set the system in a degraded state
        command = "${pkgs.runtimeShell} -c 'for pool in $(${cfgZfs.package}/bin/zpool list -H -o name); do ${cfgZfs.package}/bin/zpool trim $pool;  done || true' ";
        options.jitter = cfgTrim.randomizedDelaySec;
      };
    })
  ];
}
