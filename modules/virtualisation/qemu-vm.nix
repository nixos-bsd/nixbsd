# This module creates a virtual machine from the NixOS configuration.
# Building the `config.system.build.vm' attribute gives you a command
# that starts a KVM/QEMU VM running the NixOS configuration defined in
# `config'. By default, the Nix store is shared read-only with the
# host, which makes (re)building VMs very efficient.

{ config, lib, pkgs, options, ... }:

with lib;

let

  qemu-common = import ../../lib/qemu-common.nix { inherit lib pkgs; };

  cfg = config.virtualisation;

  opt = options.virtualisation;

  qemu = cfg.qemu.package;

  hostPkgs = cfg.host.pkgs;

  driveOpts = { ... }: {

    options = {

      file = mkOption {
        type = types.str;
        description = "The file image used for this drive.";
      };

      driveExtraOpts = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Extra options passed to drive flag.";
      };

      deviceExtraOpts = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Extra options passed to device flag.";
      };

      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = 
          "A name for the drive. Must be unique in the drives list. Not passed to qemu.";
      };

    };

  };

  selectPartitionTableLayout = { useEFIBoot, useDefaultFilesystems }:
    if useDefaultFilesystems then
      if useEFIBoot then "efi" else "legacy"
    else
      "none";

  driveCmdline = idx:
    { file, driveExtraOpts, deviceExtraOpts, ... }:
    let
      drvId = "drive${toString idx}";
      mkKeyValue = generators.mkKeyValueDefault { } "=";
      mkOpts = opts: concatStringsSep "," (mapAttrsToList mkKeyValue opts);
      driveOpts = mkOpts (driveExtraOpts // {
        index = idx;
        id = drvId;
        "if" = "none";
        inherit file;
      });
      deviceOpts = mkOpts (deviceExtraOpts // { drive = drvId; });
      device = if cfg.qemu.diskInterface == "scsi" then
        "-device lsi53c895a -device scsi-hd,${deviceOpts}"
      else
        "-device virtio-blk-pci,${deviceOpts}";
    in "-drive ${driveOpts} ${device}";

  drivesCmdLine = drives:
    concatStringsSep "\\\n    " (imap1 driveCmdline drives);

  # Shell script to start the VM.
  startVM = ''
    #! ${hostPkgs.runtimeShell}

    export PATH=${makeBinPath [ hostPkgs.coreutils ]}''${PATH:+:}$PATH

    set -e

    # Create an empty filesystem image. A filesystem image does not
    # contain a partition table but just a filesystem.
    createEmptyFilesystemImage() {
      local name=$1
      local size=$2
      local temp=$(mktemp)
      ${hostPkgs.freebsd.makefs}/bin/makefs -s "$size" -o label=${rootFilesystemLabel} "$temp"
      ${qemu}/bin/qemu-img convert -f raw -O qcow2 "$temp" "$name"
      rm "$temp"
    }

    NIX_DISK_IMAGE=$(readlink -f "''${NIX_DISK_IMAGE:-${
      toString config.virtualisation.diskImage
    }}") || test -z "$NIX_DISK_IMAGE"

    if test -n "$NIX_DISK_IMAGE" && (! test -e "$NIX_DISK_IMAGE" || ! ${qemu}/bin/qemu-img info "$NIX_DISK_IMAGE" | grep ${systemImage}/nixos.qcow2 &>/dev/null); then
        echo "Virtualisation disk image doesn't exist or needs rebase, creating..."

        ${
          if (cfg.useDefaultFilesystems) then ''
            # Create a writable qcow2 image using the systemImage as a backing
            # image.

            # CoW prevent size to be attributed to an image.
            # FIXME: raise this issue to upstream.
            ${qemu}/bin/qemu-img create \
              -f qcow2 \
              -b ${systemImage}/nixos.qcow2 \
              -F qcow2 \
              "$NIX_DISK_IMAGE"
          '' else if cfg.useDefaultFilesystems then ''
            createEmptyFilesystemImage "$NIX_DISK_IMAGE" "${
              toString cfg.diskSize
            }M"
          '' else ''
            # Create an empty disk image without a filesystem.
            ${qemu}/bin/qemu-img create -f qcow2 "$NIX_DISK_IMAGE" "${
              toString cfg.diskSize
            }M"
          ''
        }
        echo "Virtualisation disk image created."
    fi

    # Create a directory for storing temporary data of the running VM.
    if [ -z "$TMPDIR" ] || [ -z "$USE_TMPDIR" ]; then
        TMPDIR=$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)
    fi

    ${lib.optionalString (cfg.useNixStoreImage) ''
      # Create a writable copy/snapshot of the store image.
      ${qemu}/bin/qemu-img create -f qcow2 -F qcow2 -b ${storeImage}/nixos.qcow2 "$TMPDIR"/store.img
    ''}

    # Create a directory for exchanging data with the VM.
    mkdir -p "$TMPDIR/xchg"

    ${lib.optionalString cfg.useHostCerts ''
      mkdir -p "$TMPDIR/certs"
      if [ -e "$NIX_SSL_CERT_FILE" ]; then
        cp -L "$NIX_SSL_CERT_FILE" "$TMPDIR"/certs/ca-certificates.crt
      else
        echo \$NIX_SSL_CERT_FILE should point to a valid file if virtualisation.useHostCerts is enabled.
      fi
    ''}

    ${lib.optionalString cfg.useEFIBoot ''
      # Expose EFI variables, it's useful even when we are not using a bootloader (!).
      # We might be interested in having EFI variable storage present even if we aren't booting via UEFI, hence
      # no guard against `useBootLoader`.  Examples:
      # - testing PXE boot or other EFI applications
      # - directbooting LinuxBoot, which `kexec()s` into a UEFI environment that can boot e.g. Windows
      NIX_EFI_VARS=$(readlink -f "''${NIX_EFI_VARS:-${config.system.name}-efi-vars.fd}")
      # VM needs writable EFI vars
      if ! test -e "$NIX_EFI_VARS"; then
      ${
      # We still need the EFI var from the make-disk-image derivation
      # because our "switch-to-configuration" process might
      # write into it and we want to keep this data.
      ''cp ${systemImage}/efi-vars.fd "$NIX_EFI_VARS"''}
        chmod 0644 "$NIX_EFI_VARS"
      fi
    ''}

    cd "$TMPDIR"

    ${lib.optionalString (cfg.emptyDiskImages != [ ]) "idx=0"}
    ${flip concatMapStrings cfg.emptyDiskImages (size: ''
      if ! test -e "empty$idx.qcow2"; then
          ${qemu}/bin/qemu-img create -f qcow2 "empty$idx.qcow2" "${
            toString size
          }M"
      fi
      idx=$((idx + 1))
    '')}

    # Start QEMU.
    exec ${qemu-common.qemuBinary qemu} \
        -name ${config.system.name} \
        -m ${toString config.virtualisation.memorySize} \
        -smp ${toString config.virtualisation.cores} \
        -device virtio-rng-pci \
        ${concatStringsSep " " config.virtualisation.qemu.networkingOptions} \
        ${
          concatStringsSep " \\\n    " (mapAttrsToList (tag: share:
            "-virtfs local,path=${share.source},security_model=none,mount_tag=${tag}")
            config.virtualisation.sharedDirectories)
        } \
        ${drivesCmdLine config.virtualisation.qemu.drives} \
        ${concatStringsSep " \\\n    " config.virtualisation.qemu.options} \
        $QEMU_OPTS \
        "$@"
  '';

  regInfo =
    hostPkgs.closureInfo { rootPaths = config.virtualisation.additionalPaths; };

  # Use well-defined and persistent filesystem labels to identify block devices.
  rootFilesystemLabel = "nixos";
  espFilesystemLabel = "ESP"; # Hard-coded by make-disk-image.nix
  nixStoreFilesystemLabel = "nix-store";

  # The root drive is a raw disk which does not necessarily contain a
  # filesystem or partition table. It thus cannot be identified via the typical
  # persistent naming schemes (e.g. /dev/disk/by-{label, uuid, partlabel,
  # partuuid}. Instead, supply a well-defined and persistent serial attribute
  # via QEMU. Inside the running system, the disk can then be identified via
  # the /dev/fstype/id scheme.
  rootDriveSerialAttr = "root";

  # System image is akin to a complete NixOS install with
  # a boot partition and root partition.
  systemImage = import ../../lib/make-disk-image.nix {
    inherit pkgs config lib;
    contents = [{
      target = "/etc/reginfo";
      source = "${regInfo}/registration";
    }];
    format = "qcow2";
    onlyNixStore = false;
    label = rootFilesystemLabel;
    partitionTableType = selectPartitionTableLayout {
      inherit (cfg) useDefaultFilesystems useEFIBoot;
    };
    # Bootloader should be installed on the system image only if we are booting through bootloaders.
    # Though, if a user is not using our default filesystems, it is possible to not have any ESP
    # or a strange partition table that's incompatible with GRUB configuration.
    # As a consequence, this may lead to disk image creation failures.
    # To avoid this, we prefer to let the user find out about how to install the bootloader on its ESP/disk.
    # Usually, this can be through building your own disk image.
    # TODO: If a user is interested into a more fine grained heuristic for `installBootLoader`
    # by examining the actual contents of `cfg.fileSystems`, please send a PR.
    installBootLoader = cfg.useDefaultFilesystems;
    touchEFIVars = cfg.useEFIBoot;
    diskSize = "auto";
    additionalSpace = "10g";
    copyChannel = false;
    OVMF = cfg.efi.OVMF;
  };

  storeImage = import ../../lib/make-disk-image.nix {
    name = "nix-store-image";
    inherit pkgs config lib;
    additionalPaths = [ regInfo ];
    format = "qcow2";
    onlyNixStore = true;
    label = nixStoreFilesystemLabel;
    partitionTableType = "none";
    installBootLoader = false;
    touchEFIVars = false;
    diskSize = "auto";
    additionalSpace = "2g";
    copyChannel = false;
  };

in {
  options = {

    virtualisation.fileSystems = options.fileSystems;

    virtualisation.memorySize = mkOption {
      type = types.ints.positive;
      default = 1024;
      description = ''
        The memory size in megabytes of the virtual machine.
      '';
    };

    virtualisation.msize = mkOption {
      type = types.ints.positive;
      default = 16384;
      description = ''
        The msize (maximum packet size) option passed to 9p file systems, in
        bytes. Increasing this should increase performance significantly,
        at the cost of higher RAM usage.
      '';
    };

    virtualisation.diskSize = mkOption {
      type = types.nullOr types.ints.positive;
      default = 1024;
      description = ''
        The disk size in megabytes of the virtual machine.
      '';
    };

    virtualisation.diskImage = mkOption {
      type = types.nullOr types.str;
      default = "./${config.system.name}.qcow2";
      defaultText = literalExpression ''"./''${config.system.name}.qcow2"'';
      description = ''
        Path to the disk image containing the root filesystem.
        The image will be created on startup if it does not
        exist.

        If null, a tmpfs will be used as the root filesystem and
        the VM's state will not be persistent.
      '';
    };

    virtualisation.bootLoaderDevice = mkOption {
      type = types.path;
      default = "/dev/msdosfs/virtio-${rootDriveSerialAttr}";
      defaultText =
        literalExpression "/dev/msdosfs/virtio-${rootDriveSerialAttr}";
      example = "/dev/msdosfs/virtio-boot-loader-device";
      description = ''
        The path (inside th VM) to the device to boot from when legacy booting.
      '';
    };

    virtualisation.bootPartition = mkOption {
      type = types.nullOr types.path;
      default =
        if cfg.useEFIBoot then "/dev/msdosfs/${espFilesystemLabel}" else null;
      defaultText = literalExpression ''
        if cfg.useEFIBoot then "/dev/msdosfs/${espFilesystemLabel}" else null'';
      example = "/dev/msdosfs/esp";
      description = ''
        The path (inside the VM) to the device containing the EFI System Partition (ESP).

        If you are *not* booting from a UEFI firmware, this value is, by
        default, `null`. The ESP is mounted under `/boot`.
      '';
    };

    virtualisation.rootDevice = mkOption {
      type = types.nullOr types.path;
      default = "/dev/ufs/${rootFilesystemLabel}";
      defaultText = literalExpression "/dev/ufs/${rootFilesystemLabel}";
      example = "/dev/ufs/nixos";
      description = ''
        The path (inside the VM) to the device containing the root filesystem.
      '';
    };

    virtualisation.emptyDiskImages = mkOption {
      type = types.listOf types.ints.positive;
      default = [ ];
      description = ''
        Additional disk images to provide to the VM. The value is
        a list of size in megabytes of each disk. These disks are
        writeable by the VM.
      '';
    };

    virtualisation.graphics = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to run QEMU with a graphics window, or in nographic mode.
        Serial console will be enabled on both settings, but this will
        change the preferred console.
      '';
    };

    virtualisation.resolution = mkOption {
      type = options.services.xserver.resolutions.type.nestedTypes.elemType;
      default = {
        x = 1024;
        y = 768;
      };
      description = ''
        The resolution of the virtual machine display.
      '';
    };

    virtualisation.cores = mkOption {
      type = types.ints.positive;
      default = 1;
      description = ''
        Specify the number of cores the guest is permitted to use.
        The number can be higher than the available cores on the
        host system.
      '';
    };

    virtualisation.sharedDirectories = mkOption {
      type = types.attrsOf (types.submodule {
        options.source = mkOption {
          type = types.str;
          description = 
            "The path of the directory to share, can be a shell variable";
        };
        options.target = mkOption {
          type = types.path;
          description = 
            "The mount point of the directory inside the virtual machine";
        };
      });
      default = { };
      example = {
        my-share = {
          source = "/path/to/be/shared";
          target = "/mnt/shared";
        };
      };
      description = ''
        An attributes set of directories that will be shared with the
        virtual machine using VirtFS (9P filesystem over VirtIO).
        The attribute name will be used as the 9P mount tag.
      '';
    };

    virtualisation.additionalPaths = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        A list of paths whose closure should be made available to
        the VM.

        When 9p is used, the closure is registered in the Nix
        database in the VM. All other paths in the host Nix store
        appear in the guest Nix store as well, but are considered
        garbage (because they are not registered in the Nix
        database of the guest).

        When {option}`virtualisation.useNixStoreImage` is
        set, the closure is copied to the Nix store image.
      '';
    };

    virtualisation.forwardPorts = mkOption {
      type = types.listOf (types.submodule {
        options.from = mkOption {
          type = types.enum [ "host" "guest" ];
          default = "host";
          description = ''
            Controls the direction in which the ports are mapped:

            - `"host"` means traffic from the host ports
              is forwarded to the given guest port.
            - `"guest"` means traffic from the guest ports
              is forwarded to the given host port.
          '';
        };
        options.proto = mkOption {
          type = types.enum [ "tcp" "udp" ];
          default = "tcp";
          description = "The protocol to forward.";
        };
        options.host.address = mkOption {
          type = types.str;
          default = "";
          description = "The IPv4 address of the host.";
        };
        options.host.port = mkOption {
          type = types.port;
          description = "The host port to be mapped.";
        };
        options.guest.address = mkOption {
          type = types.str;
          default = "";
          description = "The IPv4 address on the guest VLAN.";
        };
        options.guest.port = mkOption {
          type = types.port;
          description = "The guest port to be mapped.";
        };
      });
      default = [ ];
      example = lib.literalExpression ''
        [ # forward local port 2222 -> 22, to ssh into the VM
          { from = "host"; host.port = 2222; guest.port = 22; }

          # forward local port 80 -> 10.0.2.10:80 in the VLAN
          { from = "guest";
            guest.address = "10.0.2.10"; guest.port = 80;
            host.address = "127.0.0.1"; host.port = 80;
          }
        ]
      '';
      description = ''
        When using the SLiRP user networking (default), this option allows to
        forward ports to/from the host/guest.

        ::: {.warning}
        If the NixOS firewall on the virtual machine is enabled, you also
        have to open the guest ports to enable the traffic between host and
        guest.
        :::

        ::: {.note}
        Currently QEMU supports only IPv4 forwarding.
        :::
      '';
    };

    virtualisation.restrictNetwork = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        If this option is enabled, the guest will be isolated, i.e. it will
        not be able to contact the host and no guest IP packets will be
        routed over the host to the outside. This option does not affect
        any explicitly set forwarding rules.
      '';
    };

    virtualisation.vlans = mkOption {
      type = types.listOf types.ints.unsigned;
      default = if config.virtualisation.interfaces == { } then [ 1 ] else [ ];
      defaultText = lib.literalExpression
        "if config.virtualisation.interfaces == {} then [ 1 ] else [ ]";
      example = [ 1 2 ];
      description = ''
        Virtual networks to which the VM is connected.  Each
        number «N» in this list causes
        the VM to have a virtual Ethernet interface attached to a
        separate virtual network on which it will be assigned IP
        address
        `192.168.«N».«M»`,
        where «M» is the index of this VM
        in the list of VMs.
      '';
    };

    virtualisation.interfaces = mkOption {
      default = { };
      example = { enp1s0.vlan = 1; };
      description = ''
        Network interfaces to add to the VM.
      '';
      type = with types;
        attrsOf (submodule {
          options = {
            vlan = mkOption {
              type = types.ints.unsigned;
              description = ''
                VLAN to which the network interface is connected.
              '';
            };

            assignIP = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Automatically assign an IP address to the network interface using the same scheme as
                virtualisation.vlans.
              '';
            };
          };
        });
    };

    virtualisation.writableStore = mkOption {
      type = types.bool;
      default = cfg.mountHostNixStore;
      defaultText = literalExpression "cfg.mountHostNixStore";
      description = ''
        If enabled, the Nix store in the VM is made writable by
        layering an overlay filesystem on top of the host's Nix
        store.

        By default, this is enabled if you mount a host Nix store.
      '';
    };

    virtualisation.writableStoreUseTmpfs = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use a tmpfs for the writable store instead of writing to the VM's
        own filesystem.
      '';
    };

    networking.primaryIPAddress = mkOption {
      type = types.str;
      default = "";
      internal = true;
      description = "Primary IP address used in /etc/hosts.";
    };

    virtualisation.host.pkgs = mkOption {
      type = options.nixpkgs.pkgs.type;
      default = pkgs.pkgsBuildBuild;
      defaultText = literalExpression "pkgs";
      example = literalExpression ''
        import pkgs.path { system = "x86_64-darwin"; }
      '';
      description = ''
        Package set to use for the host-specific packages of the VM runner.
        Changing this to e.g. a Darwin package set allows running NixOS VMs on Darwin.
      '';
    };

    virtualisation.qemu = {
      package = mkOption {
        type = types.package;
        default = hostPkgs.qemu_kvm;
        example = literalExpression "pkgs.qemu_test";
        description = "QEMU package to use.";
      };

      options = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "-vga std" ];
        description = ''
          Options passed to QEMU.
          See [QEMU User Documentation](https://www.qemu.org/docs/master/system/qemu-manpage) for a complete list.
        '';
      };

      consoles = mkOption {
        type = types.listOf types.str;
        default =
          let consoles = [ "${qemu-common.qemuSerialDevice},115200n8" "tty0" ];
          in if cfg.graphics then consoles else reverseList consoles;
        example = [ "console=tty1" ];
        description = ''
          The output console devices to pass to the kernel command line via the
          `console` parameter, the primary console is the last
          item of this list.

          By default it enables both serial console and
          `tty0`. The preferred console (last one) is based on
          the value of {option}`virtualisation.graphics`.
        '';
      };

      networkingOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "-net nic,netdev=user.0,model=virtio"
          "-netdev user,id=user.0,\${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"
        ];
        description = ''
          Networking-related command-line options that should be passed to qemu.
          The default is to use userspace networking (SLiRP).
          See the [QEMU Wiki on Networking](https://wiki.qemu.org/Documentation/Networking) for details.

          If you override this option, be advised to keep
          ''${QEMU_NET_OPTS:+,$QEMU_NET_OPTS} (as seen in the example)
          to keep the default runtime behaviour.
        '';
      };

      drives = mkOption {
        type = types.listOf (types.submodule driveOpts);
        description = "Drives passed to qemu.";
      };

      diskInterface = mkOption {
        type = types.enum [ "virtio" "scsi" "ide" ];
        default = "virtio";
        example = "scsi";
        description =
          "The interface used for the virtual hard disks.";
      };

      virtioKeyboard = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the virtio-keyboard device.
        '';
      };
    };

    virtualisation.useNixStoreImage = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Build and use a disk image for the Nix store, instead of
        accessing the host's one through 9p.

        For applications which do a lot of reads from the store,
        this can drastically improve performance, but at the cost of
        disk space and image build time.

        As an alternative, you can use a bootloader which will provide you
        with a full NixOS system image containing a Nix store and
        avoid mounting the host nix store through
        {option}`virtualisation.mountHostNixStore`.
      '';
    };

    virtualisation.mountHostNixStore = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mount the host Nix store as a 9p mount.
      '';
    };

    virtualisation.useEFIBoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        If enabled, the virtual machine will provide a EFI boot
        manager.
      '';
    };

    virtualisation.efi = {
      OVMF = mkOption {
        type = types.package;
        default =
          (hostPkgs.OVMF.override { secureBoot = cfg.useSecureBoot; }).fd;
        defaultText = ''
          (hostPkgs.OVMF.override {
                    secureBoot = cfg.useSecureBoot;
                  }).fd'';
        description = 
          "OVMF firmware package, defaults to OVMF configured with secure boot if needed.";
      };

      firmware = mkOption {
        type = types.path;
        default = cfg.efi.OVMF.firmware;
        defaultText = literalExpression "cfg.efi.OVMF.firmware";
        description = ''
          Firmware binary for EFI implementation, defaults to OVMF.
        '';
      };

      variables = mkOption {
        type = types.path;
        default = cfg.efi.OVMF.variables;
        defaultText = literalExpression "cfg.efi.OVMF.variables";
        description = ''
          Platform-specific flash binary for EFI variables, implementation-dependent to the EFI firmware.
          Defaults to OVMF.
        '';
      };
    };

    virtualisation.useDefaultFilesystems = mkOption {
      type = types.bool;
      default = true;
      description = ''
        If enabled, the boot disk of the virtual machine will be
        formatted and mounted with the default filesystems for
        testing. Swap devices and LUKS will be disabled.

        If disabled, a root filesystem has to be specified and
        formatted (for example in the initial ramdisk).
      '';
    };

    virtualisation.useSecureBoot = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable Secure Boot support in the EFI firmware.
      '';
    };

    virtualisation.bios = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        An alternate BIOS (such as `qboot`) with which to start the VM.
        Should contain a file named `bios.bin`.
        If `null`, QEMU's builtin SeaBIOS will be used.
      '';
    };

    virtualisation.useHostCerts = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, when `NIX_SSL_CERT_FILE` is set on the host,
        pass the CA certificates from the host to the VM.
      '';
    };

  };

  config = {

    assertions = lib.concatLists (lib.flip lib.imap cfg.forwardPorts (i: rule: [
      {
        assertion = rule.from == "guest" -> rule.proto == "tcp";
        message = ''
          Invalid virtualisation.forwardPorts.<entry ${toString i}>.proto:
            Guest forwarding supports only TCP connections.
        '';
      }
      {
        assertion = rule.from == "guest"
          -> lib.hasPrefix "10.0.2." rule.guest.address;
        message = ''
          Invalid virtualisation.forwardPorts.<entry ${
            toString i
          }>.guest.address:
            The address must be in the default VLAN (10.0.2.0/24).
        '';
      }
    ])) ++ [{
      assertion = pkgs.stdenv.hostPlatform.is32bit -> cfg.memorySize < 2047;
      message = ''
        virtualisation.memorySize is above 2047, but qemu is only able to allocate 2047MB RAM on 32bit max.
      '';
    }];

    warnings = optional (cfg.writableStore && cfg.useNixStoreImage
      && opt.writableStore.highestPrio > lib.modules.defaultOverridePriority) ''
        You have enabled ${opt.useNixStoreImage} = true,
        without setting ${opt.writableStore} = false.

        This causes a store image to be written to the store, which is
        costly, especially for the binary cache, and because of the need
        for more frequent garbage collection.

        If you really need this combination, you can set ${opt.writableStore}
        explicitly to true, incur the cost and make this warning go away.
        Otherwise, we recommend

          ${opt.writableStore} = false;
      '';

    boot.postMountCommands = ''
      # Mark this as a NixOS machine.
      mkdir -p $targetRoot/etc
      echo -n > $targetRoot/etc/NIXOS

      # Fix the permissions on /tmp.
      chmod 1777 $targetRoot/tmp

      mkdir -p $targetRoot/boot

      ${optionalString cfg.writableStore ''
        echo "mounting overlay filesystem on /nix/store..."
        mkdir -p -m 0755 $targetRoot/nix/.rw-store/store $targetRoot/nix/.rw-store/work $targetRoot/nix/store
        mount -t overlay overlay $targetRoot/nix/store \
          -o lowerdir=$targetRoot/nix/.ro-store,upperdir=$targetRoot/nix/.rw-store/store,workdir=$targetRoot/nix/.rw-store/work || fail
      ''}
    '';

    # After booting, register the closure of the paths in
    # `virtualisation.additionalPaths' in the Nix database in the VM.  This
    # allows Nix operations to work in the VM.  The path to the
    # registration file is passed through the kernel command line to
    # allow `system.build.toplevel' to be included.  (If we had a direct
    # reference to ${regInfo} here, then we would get a cyclic
    # dependency.)
    rc.services.loadNixRegInfo = lib.mkIf config.nix.enable {
      description = "Load nix regInfo";
      provides = "loadNixRegInfo";
      commands.start = ''
        REGINFO=/etc/reginfo
        if [[ -e "$REGINFO" ]]; then
          echo "Got reginfo '$REGINFO'"
          ${config.nix.package.out}/bin/nix-store --load-db < $REGINFO
        fi
      '';
    };

    virtualisation.additionalPaths = [ config.system.build.toplevel ];

    virtualisation.sharedDirectories = {
      nix-store = mkIf cfg.mountHostNixStore {
        source = builtins.storeDir;
        target = "/nix/store";
      };
      certs = mkIf cfg.useHostCerts {
        source = ''"$TMPDIR"/certs'';
        target = "/etc/ssl/certs";
      };
    };

    security.pki.installCACerts = mkIf cfg.useHostCerts false;

    virtualisation.qemu.networkingOptions = let
      forwardingOptions = flip concatMapStrings cfg.forwardPorts
        ({ proto, from, host, guest }:
          if from == "host" then
            "hostfwd=${proto}:${host.address}:${toString host.port}-"
            + "${guest.address}:${toString guest.port},"
          else
            "'guestfwd=${proto}:${guest.address}:${toString guest.port}-"
            + "cmd:${pkgs.netcat}/bin/nc ${host.address} ${
              toString host.port
            }',");
      restrictNetworkOption =
        lib.optionalString cfg.restrictNetwork "restrict=on,";
    in [
      "-net nic,netdev=user.0,model=virtio"
      ''
        -netdev user,id=user.0,${forwardingOptions}${restrictNetworkOption}"$QEMU_NET_OPTS"''
    ];

    virtualisation.qemu.options = mkMerge [
      (mkIf cfg.qemu.virtioKeyboard [ "-device virtio-keyboard" ])
      (mkIf pkgs.stdenv.hostPlatform.isx86 [
        "-usb"
        "-device usb-tablet,bus=usb-bus.0"
      ])
      (mkIf pkgs.stdenv.hostPlatform.isAarch [
        "-device virtio-gpu-pci"
        "-device usb-ehci,id=usb0"
        "-device usb-kbd"
        "-device usb-tablet"
      ])
      (mkIf cfg.useEFIBoot [
        "-drive if=pflash,format=raw,unit=0,readonly=on,file=${cfg.efi.firmware}"
        "-drive if=pflash,format=raw,unit=1,readonly=off,file=$NIX_EFI_VARS"
      ])
      (mkIf (cfg.bios != null) [ "-bios ${cfg.bios}/bios.bin" ])
      (mkIf (!cfg.graphics) [ "-nographic" ])
    ];

    virtualisation.qemu.drives = mkMerge [
      (mkIf (cfg.diskImage != null) [{
        name = "root";
        file = ''"$NIX_DISK_IMAGE"'';
        driveExtraOpts.cache = "writeback";
        driveExtraOpts.werror = "report";
        deviceExtraOpts.bootindex = "1";
        deviceExtraOpts.serial = rootDriveSerialAttr;
      }])
      (mkIf cfg.useNixStoreImage [{
        name = "nix-store";
        file = ''"$TMPDIR"/store.img'';
        deviceExtraOpts.bootindex = "2";
        driveExtraOpts.format = "qcow2";
      }])
      (imap0 (idx: _: {
        file = "$(pwd)/empty${toString idx}.qcow2";
        driveExtraOpts.werror = "report";
      }) cfg.emptyDiskImages)
    ];

    # By default, use mkVMOverride to enable building test VMs (e.g. via
    # `nixos-rebuild build-vm`) of a system configuration, where the regular
    # value for the `fileSystems' attribute should be disregarded (since those
    # filesystems don't necessarily exist in the VM). You can disable this
    # override by setting `virtualisation.fileSystems = lib.mkForce { };`.
    fileSystems =
      lib.mkIf (cfg.fileSystems != { }) (mkVMOverride cfg.fileSystems);

    virtualisation.fileSystems = let
      mkSharedDir = tag: share: {
        name = if tag == "nix-store" && cfg.writableStore then
          "/nix/.ro-store"
        else
          share.target;
        value.device = tag;
        value.fsType = "9p";
        #value.neededForBoot = true;
        value.options =
          [ "trans=virtio" "version=9p2000.L" "msize=${toString cfg.msize}" ]
          ++ lib.optional (tag == "nix-store") "cache=loose";
      };
    in lib.mkMerge [
      (lib.mapAttrs' mkSharedDir cfg.sharedDirectories)
      {
        "/" = lib.mkIf cfg.useDefaultFilesystems
          (if cfg.diskImage == null then {
            device = "tmpfs";
            fsType = "tmpfs";
          } else {
            device = cfg.rootDevice;
            fsType = "ufs";
          });
        "/tmp" = lib.mkIf config.boot.tmp.useTmpfs {
          device = "tmpfs";
          fsType = "tmpfs";
          #neededForBoot = true;
          # Sync with systemd's tmp.mount;
          options = [
            "mode=1777"
            "nosuid"
            "size=${toString config.boot.tmp.tmpfsSize}"
          ];
        };
        "/nix/${if cfg.writableStore then ".ro-store" else "store"}" =
          lib.mkIf cfg.useNixStoreImage {
            device = "/dev/disk/by-label/${nixStoreFilesystemLabel}";
            #neededForBoot = true;
            options = [ "ro" ];
          };
        "/nix/.rw-store" =
          lib.mkIf (cfg.writableStore && cfg.writableStoreUseTmpfs) {
            fsType = "tmpfs";
            options = [ "mode=0755" ];
            #neededForBoot = true;
          };
        "/boot" = lib.mkIf (cfg.bootPartition != null) {
          device = cfg.bootPartition;
          fsType = "msdosfs";
          noCheck = true; # fsck fails on a r/o filesystem
        };
      }
    ];

    swapDevices =
      (if cfg.useDefaultFilesystems then mkVMOverride else mkDefault) [ ];

    system.build.vm = hostPkgs.runCommand "nixos-vm" {
      preferLocalBuild = true;
      meta.mainProgram = "run-${config.system.name}-vm";
    } ''
      mkdir -p $out/bin
      ln -s ${config.system.build.toplevel} $out/system
      ln -s ${
        hostPkgs.writeScript "run-nixos-vm" startVM
      } $out/bin/run-${config.system.name}-vm
    '';

    system.build.systemImage = systemImage;

    # TODO: enable guest agent when it exists
    # TODO: disable ntpd when it exists
    # TODO: configure xserver
    # TODO: disable wireless when it exists

    # Speed up booting by not waiting for ARP.
    networking.dhcpcd.extraConfig = "noarp";

  };

  # uses types of services/x11/xserver.nix
  meta.buildDocsInSandbox = false;
}
