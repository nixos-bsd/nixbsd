{ config, lib, pkgs, utils, ... }:

with lib;
with utils;

let

  addCheckDesc = desc: elemType: check:
    types.addCheck elemType check // {
      description = "${elemType.description} (with check: ${desc})";
    };

  isNonEmpty = s:
    (builtins.match ''
      [ 	
      ]*'' s) == null;
  nonEmptyStr = addCheckDesc "non-empty" types.str isNonEmpty;

  fileSystems' = toposort fsBefore (attrValues config.fileSystems);

  fileSystems = if fileSystems'
  ? result then # use topologically sorted fileSystems everywhere
    fileSystems'.result
  else # the assertion below will catch this,
  # but we fall back to the original order
  # anyway so that other modules could check
  # their assertions too
    (attrValues config.fileSystems);

  specialFSTypes =
    [ "devfs" "procfs" "sysfs" "tmpfs" "ramfs" "devtmpfs" "devpts" "fdescfs" ];

  nonEmptyWithoutTrailingSlash =
    addCheckDesc "non-empty without trailing slash" types.str
    (s: isNonEmpty s && (builtins.match ".+/" s) == null);

  coreFileSystemOpts = { name, config, ... }: {
    options = {
      mountPoint = mkOption {
        example = "/mnt/usb";
        type = nonEmptyWithoutTrailingSlash;
        description = lib.mdDoc "Location of the mounted file system.";
      };

      device = mkOption {
        default = null;
        example = "/dev/ada0p1";
        type = types.nullOr nonEmptyStr;
        description = lib.mdDoc "Location of the device.";
      };

      fsType = mkOption {
        default = "auto";
        example = "ext3";
        type = nonEmptyStr;
        description = lib.mdDoc "Type of the file system.";
      };

      options = mkOption {
        default = [ ];
        example = [ "data=journal" ];
        description = lib.mdDoc "Options used to mount the file system.";
        type = types.listOf nonEmptyStr;
      };

      depends = mkOption {
        default = [ ];
        example = [ "/persist" ];
        type = types.listOf nonEmptyWithoutTrailingSlash;
        description = lib.mdDoc ''
          List of paths that should be mounted before this one. This filesystem's
          {option}`device` and {option}`mountPoint` are always
          checked and do not need to be included explicitly. If a path is added
          to this list, any other filesystem whose mount point is a parent of
          the path will be mounted before this filesystem. The paths do not need
          to actually be the {option}`mountPoint` of some other filesystem.
        '';
      };

      writable = mkOption {
        default = true;
        example = false;
        type = types.bool;
        description = lib.mdDoc "Mount the filesystem as read/write.";
      };
    };

    config = {
      mountPoint = mkDefault name;
      device =
        mkIf (elem config.fsType specialFSTypes) (mkDefault config.fsType);
    };

  };

  fileSystemOpts = { config, ... }: {
    options = {
      label = mkOption {
        default = null;
        example = "root-partition";
        type = types.nullOr nonEmptyStr;
        description = lib.mdDoc "Label of the device (if any).";
      };

      noCheck = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc "Disable running fsck on this filesystem.";
      };
    };
  };

  # Makes sequence of `specialMount device mountPoint options fsType` commands.
  # `systemMount` should be defined in the sourcing script.
  makeSpecialMounts = mounts:
    pkgs.writeText "mounts.sh" (concatMapStringsSep "\n" (mount: ''
      specialMount "${mount.device}" "${mount.mountPoint}" "${
        concatStringsSep "," mount.options
      }" "${mount.fsType}"
    '') mounts);

  makeFstabEntries = let
    fsToSkipCheck = [
      "none"
      "auto"
      "overlay"
      "iso9660"
      "bindfs"
      "udf"
      "btrfs"
      "zfs"
      "tmpfs"
      "bcachefs"
      "nfs"
      "nfs4"
      "nilfs2"
      "vboxsf"
      "squashfs"
      "glusterfs"
      "apfs"
      "9p"
      "cifs"
      "prl_fs"
      "vmhgfs"
    ];
    isBindMount = fs: builtins.elem "bind" fs.options;
    skipCheck = fs:
      fs.noCheck || fs.device == "none" || builtins.elem fs.fsType fsToSkipCheck
      || isBindMount fs;
    # https://wiki.archlinux.org/index.php/fstab#Filepath_spaces
    escape = string:
      builtins.replaceStrings [ " " "	" ] [ "\\040" "\\011" ] string;
    fsOptions = fs: (if fs.writable then [ "rw" ] else [ "ro" ]) ++ fs.options;
  in fstabFileSystems:
  { }:
  concatMapStrings (fs:
    escape fs.device + " " + escape fs.mountPoint + " " + fs.fsType + " "
    + escape (builtins.concatStringsSep "," (fsOptions fs)) + " 0 "
    + (if skipCheck fs then "0" else if fs.mountPoint == "/" then "1" else "2")
    + "\n") fstabFileSystems;

in {

  ###### interface

  options = {

    fileSystems = mkOption {
      default = { };
      example = literalExpression ''
        {
          "/".device = "/dev/hda1";
          "/data" = {
            device = "/dev/hda2";
            fsType = "ext3";
            options = [ "data=journal" ];
          };
          "/bigdisk".label = "bigdisk";
        }
      '';
      type =
        types.attrsOf (types.submodule [ coreFileSystemOpts fileSystemOpts ]);
      description = lib.mdDoc ''
        The file systems to be mounted.  It must include an entry for
        the root directory (`mountPoint = "/"`).  Each
        entry in the list is an attribute set with the following fields:
        `mountPoint`, `device`,
        `fsType` (a file system type recognised by
        {command}`mount`; defaults to
        `"auto"`), and `options`
        (the mount options passed to {command}`mount` using the
        {option}`-o` flag; defaults to `[ "defaults" ]`).

        Instead of specifying `device`, you can also
        specify a volume label (`label`) for file
        systems that support it, such as ext2/ext3 (see {command}`mke2fs -L`).
      '';
    };

    system.fsPackages = mkOption {
      internal = true;
      default = [ ];
      description =
        lib.mdDoc "Packages supplying file system mounters and checkers.";
    };

    boot.supportedFilesystems = mkOption {
      default = [ ];
      example = [ "btrfs" ];
      type = types.listOf types.str;
      description = lib.mdDoc "Names of supported filesystem types.";
    };

    boot.specialFileSystems = mkOption {
      default = { };
      type = types.attrsOf (types.submodule coreFileSystemOpts);
      internal = true;
      description = lib.mdDoc ''
        Special filesystems that are mounted very early during boot.
      '';
    };

    boot.devSize = mkOption {
      default = "5%";
      example = "32m";
      type = types.str;
      description = lib.mdDoc ''
        Size limit for the /dev tmpfs. Look at mount(8), tmpfs size option,
        for the accepted syntax.
      '';
    };

    boot.devShmSize = mkOption {
      default = "50%";
      example = "256m";
      type = types.str;
      description = lib.mdDoc ''
        Size limit for the /dev/shm tmpfs. Look at mount(8), tmpfs size option,
        for the accepted syntax.
      '';
    };

    boot.runSize = mkOption {
      default = "25%";
      example = "256m";
      type = types.str;
      description = lib.mdDoc ''
        Size limit for the /run tmpfs. Look at mount(8), tmpfs size option,
        for the accepted syntax.
      '';
    };

    boot.mountProcfs = mkOption {
      default = false;
      type = types.bool;
      description = lib.mkDoc ''
        Whether to mount /proc at boot. This is considered deprecated behavior by FreeBSD.
      '';
    };
  };

  ###### implementation

  config = {

    assertions = let ls = sep: concatMapStringsSep sep (x: x.mountPoint);
    in [{
      assertion = !(fileSystems' ? cycle);
      message =
        "The ‘fileSystems’ option can't be topologically sorted: mountpoint dependency path ${
          ls " -> " fileSystems'.cycle
        } loops to ${ls ", " fileSystems'.loops}";
    }];

    # Export for use in other modules
    system.build.fileSystems = fileSystems;
    system.build.earlyMountScript = makeSpecialMounts
      (toposort fsBefore (attrValues config.boot.specialFileSystems)).result;

    boot.supportedFilesystems = map (fs: fs.fsType) fileSystems;

    # Add the mount helpers to the system path so that `mount' can find them.
    system.fsPackages = [ pkgs.freebsd.mount_msdosfs ];

    environment.systemPackages = with pkgs;
      [ freebsd.mount ] ++ config.system.fsPackages;

    environment.etc.fstab.text =
      let swapOptions = sw: concatStringsSep "," ([ "sw" ] ++ sw.options);
      in ''
        # This is a generated file.  Do not edit!
        # To make changes, rebuild your system.
        #
        # Device	       Mountpoint      FStype  Options	       Dump    Pass#
        #

        # Filesystems.
        ${makeFstabEntries fileSystems { }}

        # Swap devices.
        ${flip concatMapStrings config.swapDevices (sw: ''
          ${sw.realDevice} none swap ${swapOptions sw}
        '')}
      '';

    # Sync mount options with systemd's src/core/mount-setup.c: mount_table.
    boot.specialFileSystems = {
      "/run" = {
        fsType = "tmpfs";
        options = [ "nosuid" "mode=755" "size=${config.boot.runSize}" ];
      };
    } // (optionalAttrs (config.boot.mountProcfs) {
      "/proc" = {
        fsType = "procfs";
        options = [ "nosuid" "noexec" "nodev" ];
      };
    });

    rc.services.mountcritlocal = {
      description = "Mount local filesystems";
      provides = "mountcritlocal";
      requires = [ "root" ];
      before = [ "FILESYSTEMS" ];
      keywordShutdown = true;
      keywordNojail = true;
      binDeps = with pkgs;
        [ freebsd.mount freebsd.bin freebsd.limits coreutils ]
        ++ config.system.fsPackages;

      commands.stop = "sync";
      commands.start = ''
        startmsg -n 'Mounting local filesystems:'
        mount -a -t "nonfs,smbfs"
        err=$?
        if [ $err -ne 0 ]; then
          echo 'Mounting /etc/fstab filesystems failed,' \
              'will retry after root mount hold release'
          root_hold_wait
          mount -a -t "nonfs,smbfs"
          err=$?
        fi

        startmsg '.'

        case $err in
        0)
          ;;
        *)
          echo 'Mounting /etc/fstab filesystems failed,' \
              'startup aborted'
          stop_boot true
          ;;
        esac
      '';
    };
  };
}
