{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
with lib;
let
  # filesystem dependency logic
  mountStrlen = x: builtins.toString ((builtins.stringLength x) + 1);
  succAncestor = path: if path == "/" then [ ] else [ (builtins.dirOf path) ];
  succDeps = path: (config.fileSystems.${path} or { }).depends or [ ];
  succ = path: (succAncestor path) ++ (succDeps path);
  newEntries =
    old: entries:
    lib.lists.ifilter0 (
      i: val: !(builtins.elem val old) && !(builtins.elem val (lib.lists.sublist 0 i entries))
    ) entries;
  fsDepClosure' =
    currentEntries: frontier:
    let
      newerEntries = lib.lists.flatten (builtins.map succ frontier);
      newestEntries = newEntries currentEntries newerEntries;
      continue = newestEntries != [ ];
      currenterEntries = currentEntries ++ newestEntries;
      recurse = fsDepClosure' currenterEntries newestEntries;
    in
    newestEntries ++ lib.optionals continue recurse;
  fsDepClosure = startEntries: startEntries ++ fsDepClosure' startEntries startEntries;
  critClosure = fsDepClosure config.boot.initmd.pivotFileSystems;
  critMountpoints = builtins.filter (path: config.fileSystems ? ${path}) critClosure;
  sortedCritMountpointsRaw = (
    lib.lists.toposort (
      a: b: utils.fsBefore config.fileSystems.${a} config.fileSystems.${b}
    ) critMountpoints
  );
  sortedCritMountpoints =
    sortedCritMountpointsRaw.result
      or (throw "cycle: ${builtins.toString sortedCritMountpointsRaw.cycle}\nloops: ${builtins.toString sortedCritMountpointsRaw.loops}");
  sortedCritMountpointsNoRoot = builtins.filter (path: path != "/") sortedCritMountpoints;

  # Get all parent directories that need to be created
  getAllParents =
    path: if path == "/" || path == "" then [ ] else [ path ] ++ (getAllParents (dirOf path));

  # Get unique sorted list of all directories to create (excluding mount points themselves)
  allDirsToCreate = lib.unique (
    lib.sort (a: b: (builtins.stringLength a) < (builtins.stringLength b)) (
      lib.flatten (
        map (
          mp:
          let
            parents = getAllParents (dirOf mp);
          in
          filter (p: p != "/" && !(lib.elem p sortedCritMountpointsNoRoot)) parents
        ) sortedCritMountpointsNoRoot
      )
    )
  );

  # MDImage mounts (similar to linux loop)
  loopFilesystems = builtins.attrNames (
    lib.filterAttrs (n: v: builtins.elem "loop" v.options) config.fileSystems
  );

  # generating c code
  cStringLit = val: "\"${builtins.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] val}\"";
  mkFilesystemMountC' =
    fs:
    let
      entries = [
        {
          name = "fstype";
          valueLit = fs.fsType;
        }
        {
          name = "from";
          valueLit = if isLoop then "/dev/md66" else fs.device;
        }
        {
          name = "fspath";
          valueLit = fs.target;
        }
        {
          name = "errmsg";
          valueVar = "errmsg";
          valueLen = "sizeof(errmsg)";
        }
      ]
      ++ builtins.map (
        option:
        let
          split = lib.strings.splitString "=" option;
          name = builtins.elemAt split 0;
          values = lib.lists.sublist 1 ((builtins.length split) - 1) split;
          valueLit = lib.strings.concatStringsSep "=" values;
        in
        {
          inherit name valueLit;
        }
      ) (builtins.filter (x: x != "loop") fs.options);
      toEntryC =
        entry:
        "{ .iov_base = (void*)${cStringLit entry.name}, .iov_len = ${mountStrlen entry.name} }, { .iov_base = (void*)${
          if entry ? valueLit then cStringLit entry.valueLit else entry.valueVar
        }, .iov_len = ${if entry ? valueLit then mountStrlen entry.valueLit else entry.valueLen} }";
      entriesList = lib.strings.concatStringsSep ", " (builtins.map toEntryC entries);
      count = builtins.toString ((builtins.length entries) * 2);

      isLoop = (builtins.elem "loop" fs.options);
      isRO = (builtins.elem "ro" fs.options);
      mkMDConfig = optionalString isLoop ''
        {
          struct stat st;
          if (stat(${cStringLit fs.device}, &st) == 0) {
            printf("init0: ${fs.device}: size: %lld bytes\n", (long long)st.st_size);

            // Prepare md ioctl structure
            struct md_ioctl mdio;
            bzero(&mdio, sizeof(mdio));
            mdio.md_file = malloc(PATH_MAX);
            mdio.md_label = malloc(PATH_MAX);
            if (mdio.md_file == NULL || mdio.md_label == NULL)
              printf("init0: warning: mountMD could not allocate mdIO struct memory");
            bzero(mdio.md_file, PATH_MAX);
            bzero(mdio.md_label, PATH_MAX);

            char* imgFile = ${cStringLit fs.device};

            mdio.md_version = MDIOVERSION;
            mdio.md_unit = 66;
            mdio.md_type = MD_VNODE;
            ${lib.optionalString isRO "mdio.md_options |= MD_READONLY;"}
            mdio.md_mediasize = st.st_size;
            mdio.md_file = strdup(imgFile);

            fd = open(mdio.md_file, O_RDONLY);
            if (fd < 0)
              printf("init0: warning: mountMD could not open %s", imgFile);
            if (!S_ISREG(st.st_mode))
              printf("init0: warning: mountMD: %s is not a regular file", imgFile);
            
            close(fd);

            // Import "Loop" image before mounting
            printf("init0: attempting to attach %s as memory disk\n", ${cStringLit fs.device});
            if (ioctl(md_fd, MDIOCATTACH, &mdio) < 0) {
                printf("init0: warning: %s memory disk import failed: %s (errno=%d)\n", ${cStringLit fs.fsType}, strerror(errno), errno);
            }
          } else {
            printf("init0: warning: %s memory disk file does not exists\n", ${cStringLit fs.fsType});
          }
        }
      '';
    in
    ''
      ${concatMapStrings (dep: ''
        mkdir(${cStringLit dep}, 0755);
      '') fs.depends}
      mkdir(${cStringLit fs.target}, 0755);
      printf("init0: attempting to mount %s:%s onto %s\n", ${cStringLit fs.fsType}, ${cStringLit fs.device}, ${cStringLit fs.target});
      ${mkMDConfig}
      if (nmount((struct iovec[${count}]){${entriesList}}, ${count}, 0) < 0) {
          printf("init0: nmount: %s:%s onto %s: %s (%s)\n", ${cStringLit fs.fsType}, ${cStringLit fs.device}, ${cStringLit fs.target}, errmsg, strerror(errno));
          return 21;
      }
      printf("init0: %s:%s onto %s: success\n", ${cStringLit fs.fsType}, ${cStringLit fs.device}, ${cStringLit fs.target});
    '';
  mkFilesystemMountC =
    fs:
    let
      split = lib.strings.splitString ":" fs.device;
      bottomLayerIdx = (builtins.length split) - 1;
      bottomLayer = builtins.elemAt split bottomLayerIdx;
      unionLayers = lib.lists.reverseList (lib.lists.sublist 0 bottomLayerIdx split);

      bindMount' = mkFilesystemMountC' {
        inherit (fs) target depends;
        fsType = "nullfs";
        device = bottomLayer;
        options = [ ];
      };
      bindMount = lib.optionalString (bottomLayer != fs.target) bindMount';
      unionMount = (
        lib.concatMapStrings (
          layer:
          mkFilesystemMountC' {
            inherit (fs) target;
            fsType = "unionfs";
            device = layer;
            depends = [ ];
            options = [ ];
          }
        ) unionLayers
      );
    in
    if fs.fsType == "unionfs" then bindMount + unionMount else mkFilesystemMountC' fs;
  mkFilesystemMountptC =
    target: mkFilesystemMountC (config.fileSystems.${target} // { inherit target; });
  critMountsC = lib.concatMapStrings mkFilesystemMountptC sortedCritMountpointsNoRoot;

  mdInit = lib.optionalString (loopFilesystems != []) ''
    const char *md_device = "/dev/mdctl";
    int md_fd;

    printf("init0: initializing MDImage control channel at %s", md_device);
    // Open the control device
    md_fd = open(md_device, O_RDWR);
    if (md_fd < 0) {
        printf("init0: warning: failed to open %s, continuing anyway", md_device);
    }
  '';

  mdClose = lib.optionalString (loopFilesystems != []) ''
    close(md_fd)
  '';

  init0_src = ''
    #include <stdio.h>
    #include <stdlib.h>
    #include <sys/param.h>
    #include <sys/mount.h>
    #include <sys/mdioctl.h>
    #include <sys/ioctl.h>
    #include <sys/uio.h>
    #include <sys/reboot.h>
    #include <sys/stat.h>
    #include <sys/wait.h>
    #include <kenv.h>
    #include <errno.h>
    #include <unistd.h>
    #include <string.h>
    #include <strings.h>
    #include <fcntl.h>

    int main(int argc, char **argv, char **envp) {
        char errmsg[256] = "";
        char *mountfrom = "${config.fileSystems."/".fsType}:${
          lib.optionalString (config.fileSystems."/".fsType != "tmpfs") config.fileSystems."/".device
        }";
        char *fstype = "${config.fileSystems."/".fsType}";

        int ret;
        
        printf("init0: starting, setting vfs.root.mountfrom=%s\n", mountfrom);
        
        if (kenv(KENV_SET, "vfs.root.mountfrom", mountfrom, strlen(mountfrom) + 1) < 0) {
            perror("init0: kenv(KENV_SET)");
            return 6;
        }
        close(0);
        close(1);
        close(2);
        unmount("/dev", 0);
        
        printf("init0: calling reboot(RB_REROOT)\n");
        if (reboot(RB_REROOT) < 0) {
            perror("init0: reboot(RB_REROOT)");
            return 5;
        }
        
        chdir("/");
        struct iovec iov3[10] = {
            { .iov_base = (void*)"fstype", .iov_len = sizeof("fstype") },
            { .iov_base = (void*)fstype, .iov_len = strlen(fstype) + 1 },
            { .iov_base = (void*)"fspath", .iov_len = sizeof("fspath") },
            { .iov_base = (void*)"/", .iov_len = sizeof("/") },
            { .iov_base = (void*)"noro", .iov_len = sizeof("noro") },
            { .iov_base = (void*)"", .iov_len = sizeof("") },
            { .iov_base = (void*)"errmsg", .iov_len = sizeof("errmsg") },
            { .iov_base = (void*)errmsg, .iov_len = sizeof(errmsg) },
        };
        if (nmount(iov3, 8, MNT_UPDATE | MNT_NOATIME) < 0) {
            fprintf(stderr, "init0: nmount root update: %s\n", errmsg);
            return 102;
        }
        if (mkdir("/dev", 0755) < 0) {
            if (errno != EEXIST) {
                printf("init0: mkdir /dev failed: %s\n", strerror(errno));
                return 49;
            }
        }
        struct iovec iov4[6] = {
            { .iov_base = (void*)"fstype", .iov_len = sizeof("fstype") },
            { .iov_base = (void*)"devfs", .iov_len = sizeof("devfs") },
            { .iov_base = (void*)"fspath", .iov_len = sizeof("fspath") },
            { .iov_base = (void*)"/dev", .iov_len = sizeof("/dev") },
            { .iov_base = (void*)"errmsg", .iov_len = sizeof("errmsg") },
            { .iov_base = (void*)errmsg, .iov_len = sizeof(errmsg) },
        };
        if (nmount(iov4, 6, 0) < 0) {
            fprintf(stderr, "init0: nmount devfs: %s\n", errmsg);
            return 48;
        }
        int fd = open("/dev/console", O_RDWR);
        if (fd < 0) {
          printf("init0: open /dev/console failed: %s\n", strerror(errno));
          return 103;
        }
        if (fd != 0) {
          printf("init0: /dev/console fd is %d, not 0\n", fd);
          return 104;
        }
        dup2(fd, 1);
        dup2(fd, 2);
        printf("init0: successfully pivoted root and mounted devfs\n");
        
        mkdir("/etc", 0755);
        mkdir("/run", 0755);
        mkdir("/tmp", 0755);
        mkdir("/sbin", 0755);
        
        ${concatMapStrings (dir: ''
          mkdir(${cStringLit dir}, 0755);
        '') allDirsToCreate}
      
        ${mdInit} // Optional MDImage Init
      
        ${critMountsC}

        ${mdClose} // Optional MDImage close
        
        char init1_path[256];
        if (kenv(KENV_GET, "init1_path", init1_path, sizeof(init1_path)) < 0) {
            printf("init0: kenv(KENV_GET, init1_path): %s\n", strerror(errno));
            return 2;
        }
        
        printf("init0: execing init1 at %s\n", init1_path);
        argv[0] = init1_path;
        execve(init1_path, argv, envp);
        perror("init0: execve");
        return 1;
    }
  '';
in
{
  options = {
    boot.initmd.enable = mkEnableOption "Boot from a memory disk";
    boot.initmd.contents = mkOption {
      type = types.listOf types.pathInStore;
      description = ''
        Paths to include in the initmd image.
      '';
      default = [ ];
    };
    boot.initmd.image = mkOption {
      type = types.path;
      description = ''
        The initmd image.
      '';
    };
    boot.initmd.pivotFileSystems = mkOption {
      type = types.listOf types.str;
      description = ''
        The filesystems that need to be mounted or re-mounted in order to pivot to the next stage of initialization.
      '';
      default = [ ];
    };
    boot.initmd.init0_src = mkOption {
      type = types.str;
      description = "For debugging";
      default = init0_src;
      internal = true;
      readOnly = true;
    };
  };
  config = mkIf config.boot.initmd.enable {
    assertions = [
      {
        # Syslinux (and isolinux) only supports x86-based architectures.
        assertion = builtins.length loopFilesystems <= 1;
        message = ''Cannot have multiple "loop" device {TODO: FOR NOW} -> ${builtins.toJSON loopFilesystems}'';
      }
    ];

    boot.initmd.image = import ../../../lib/make-partition-image.nix {
      inherit pkgs lib;
      label = "initmd";
      filesystem = "ufs";
      nixStorePath = "/nix/store";
      nixStoreClosure = config.boot.initmd.contents;
      makeRootDirs = true;
    };

    boot.initmd.contents = [
      config.boot.kernelEnvironment.init0_path # Need Memory Disk for ISO Images
    ] ++ lib.optional (loopFilesystems != []) pkgs.freebsd.mdconfig;

    boot.kernelEnvironment.init0_path = builtins.toString (
      pkgs.pkgsStatic.runCommandCC "init0" { } ''
        $CC -x c -o $out - <<INIT0EOF
        ${init0_src}
        INIT0EOF
      ''
    );
    boot.kernelEnvironment."vfs.root.mountfrom" = lib.mkOverride 20 "ufs:/dev/md0";
    boot.kernelEnvironment."vfs.root.mountfrom.options" = lib.mkOverride 20 "";
  };
}
