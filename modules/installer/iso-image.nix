# This module creates a bootable ISO image containing the given NixOS
# configuration.  The derivation for the ISO image will be placed in
# config.system.build.isoImage.
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  inherit (lib)
    generators
    types
    flip
    imap0
    imap1
    literalExpression
    reverseList
    mkVMOverride
    mkDefault
    mkMerge
    mkIf
    mkOption
    concatMapStrings
    concatStringsSep
    makeBinPath
    mapAttrsToList
    getExe
    ;
in
let
  makedev-mtree = pkgs.openbsd.callPackage ../../lib/openbsd-makedev-mtree.nix { };

  cfg = config.virtualisation;
  opt = options.virtualisation;

  hostPkgs = cfg.host.pkgs;

  regInfo = hostPkgs.closureInfo { rootPaths = config.virtualisation.additionalPaths; };

  espFilesystemLabel = "ESP"; # Hard-coded by make-disk-image.nix

  inherit (config.boot.loader) espContents;

  efiImg = pkgs.callPackage ../../lib/make-partition-image.nix {
    inherit pkgs lib;
    label = espFilesystemLabel;
    filesystem = "efi";
    noSymlinks = true;
    contents = [
      {
        target = "/";
        source =
          if config.boot.loader.espContents == null then
            throw "The bootloader configuration did not provide an EFI system partition but the drive layout is asking for it!"
          else
            config.boot.loader.espContents;
      }
    ];
    totalSize = "384m";
  };
in
{
  imports = [
    (lib.mkRenamedOptionModuleWith {
      sinceRelease = 2505;
      from = [
        "isoImage"
        "isoBaseName"
      ];
      to = [
        "image"
        "baseName"
      ];
    })
    (lib.mkRenamedOptionModuleWith {
      sinceRelease = 2505;
      from = [
        "isoImage"
        "isoName"
      ];
      to = [
        "image"
        "fileName"
      ];
    })

    ../image/file-options.nix
  ];

  options = {

    isoImage.compressImage = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Whether the ISO image should be compressed using
        {command}`xz`.
      '';
    };

    isoImage.squashfsCompression = lib.mkOption {
      default = "zstd -Xcompression-level 19";
      type = lib.types.nullOr lib.types.str;
      description = ''
        Compression settings to use for the squashfs nix store.
        `null` disables compression.
      '';
      example = "zstd -Xcompression-level 6";
    };

    isoImage.edition = lib.mkOption {
      default = "";
      type = lib.types.str;
      description = ''
        Specifies which edition string to use in the volume ID of the generated
        ISO image.
      '';
    };

    isoImage.volumeID = lib.mkOption {
      # nixos-$EDITION-$RELEASE-$ARCH
      default = lib.toUpper (
        lib.replaceStrings [ "." "-" ] [ "_" "_" ]
          "nixbsd${
            lib.optionalString (config.isoImage.edition != "") "-${config.isoImage.edition}"
          }-${config.system.nixos.release}-${pkgs.stdenv.hostPlatform.uname.processor}"
      );
      type = lib.types.strMatching "[A-Z0-9_]+";
      description = ''
        Specifies the label or volume ID of the generated ISO image.
        Note that the label is used by stage 1 of the boot process to
        mount the CD, so it should be reasonably distinctive.
      '';
    };

    isoImage.contents = lib.mkOption {
      example = lib.literalExpression ''
        [ { source = pkgs.memtest86 + "/memtest.bin";
            target = "boot/memtest.bin";
          }
        ]
      '';
      description = ''
        This option lists files to be copied to fixed locations in the
        generated ISO image.
      '';
    };

    isoImage.storeContents = lib.mkOption {
      example = lib.literalExpression "[ pkgs.stdenv ]";
      description = ''
        This option lists additional derivations to be included in the
        Nix store in the generated ISO image.
      '';
    };

    isoImage.includeSystemBuildDependencies = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Set this option to include all the needed sources etc in the
        image. It significantly increases image size. Use that when
        you want to be able to keep all the sources needed to build your
        system or when you are going to install the system on a computer
        with slow or non-existent network connection.
      '';
    };

    isoImage.makeBiosBootable = lib.mkOption {
      # Before this option was introduced, images were BIOS-bootable if the
      # hostPlatform was x86-based. This option is enabled by default for
      # backwards compatibility.
      #
      # Also note that syslinux package currently cannot be cross-compiled from
      # non-x86 platforms, so the default is false on non-x86 build platforms.
      default =
        !pkgs.stdenv.hostPlatform.isBSD
        && pkgs.stdenv.buildPlatform.isx86
        && pkgs.stdenv.hostPlatform.isx86;
      defaultText = lib.literalMD ''
        `true` if both build and host platforms are x86-based architectures,
        e.g. i686 and x86_64.
      '';
      type = lib.types.bool;
      description = ''
        Whether the ISO image should be a BIOS-bootable disk.
      '';
    };

    isoImage.makeEfiBootable = lib.mkOption {
      default = true; # TODO: test true
      type = lib.types.bool;
      description = ''
        Whether the ISO image should be an EFI-bootable volume.
      '';
    };

    isoImage.makeUsbBootable = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Whether the ISO image should be bootable from CD as well as USB.
      '';
    };

    isoImage.efiSplashImage = lib.mkOption {
      default = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/a9e05d7deb38a8e005a2b52575a3f59a63a4dba0/bootloader/efi-background.png";
        sha256 = "18lfwmp8yq923322nlb9gxrh5qikj1wsk6g5qvdh31c4h5b1538x";
      };
      description = ''
        The splash image to use in the EFI bootloader.
      '';
    };

    isoImage.splashImage = lib.mkOption {
      default = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/a9e05d7deb38a8e005a2b52575a3f59a63a4dba0/bootloader/isolinux/bios-boot.png";
        sha256 = "1wp822zrhbg4fgfbwkr7cbkr4labx477209agzc0hr6k62fr6rxd";
      };
      description = ''
        The splash image to use in the legacy-boot bootloader.
      '';
    };

    isoImage.grubTheme = lib.mkOption {
      default = if pkgs.stdenv.hostPlatform.isFreeBSD then null else pkgs.nixos-grub2-theme; # TODO: default
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.package);
      description = ''
        The grub2 theme used for UEFI boot.
      '';
    };

    isoImage.prependToMenuLabel = lib.mkOption {
      default = "";
      type = lib.types.str;
      example = "Install ";
      description = ''
        The string to prepend before the menu label for the NixOS system.
        This will be directly prepended (without whitespace) to the NixOS version
        string, like for example if it is set to `XXX`:

        `XXXNixOS 99.99-pre666`
      '';
    };

    isoImage.appendToMenuLabel = lib.mkOption {
      default = " Installer";
      type = lib.types.str;
      example = " Live System";
      description = ''
        The string to append after the menu label for the NixOS system.
        This will be directly appended (without whitespace) to the NixOS version
        string, like for example if it is set to `XXX`:

        `NixOS 99.99-pre666XXX`
      '';
    };

    isoImage.configurationName = lib.mkOption {
      default = null;
      type = lib.types.nullOr lib.types.str;
      example = "GNOME";
      description = ''
        The name of the configuration in the title of the boot entry.
      '';
    };

    isoImage.showConfiguration = lib.mkEnableOption "show this configuration in the menu" // {
      default = true;
    };

    isoImage.forceTextMode = lib.mkOption {
      default = false;
      type = lib.types.bool;
      example = true;
      description = ''
        Whether to use text mode instead of graphical grub.
        A value of `true` means graphical mode is not tried to be used.

        This is useful for validating that graphics mode usage is not at the root cause of a problem with the iso image.

        If text mode is required off-handedly (e.g. for serial use) you can use the `T` key, after being prompted, to use text mode for the current boot.
      '';
    };
  };

  # /nix/store
  config.readOnlyNixStore = {
    enable = true;
    readOnlySource = "/squash/nix/store";
    writableLayer = "/nix/.rw-store";
  };

  # store them in lib so we can mkImageMediaOverride the
  # entire file system layout in installation media (only)
  config.lib.isoFileSystems =
    let
      inherit (config.readOnlyNixStore) readOnlySource writableLayer;
    in
    {
      "/" = lib.mkImageMediaOverride {
        device = "tmpfs";
        fsType = "tmpfs";
        # options = [ "data=journal" ];
      };

      "/iso" = lib.mkImageMediaOverride {
        device = "/dev/iso9660/${config.isoImage.volumeID}";
        fsType = "cd9660";
        options = [ ];
        neededForBoot = true;
        noCheck = true;
      };

      # Directly in ISO /rootFS
      "/squash" = lib.mkImageMediaOverride {
        fsType = "ufs";
        device = "/iso/nix/store.img";
        options = [
          "loop"
          "ro"
        ];
        neededForBoot = true;
        depends = [ "/iso" ];
      };

      "${writableLayer}" = lib.mkImageMediaOverride {
        fsType = "tmpfs";
        options = [ "mode=0755" ];
        neededForBoot = true;
      };

      "/nix/store" = lib.mkImageMediaOverride {
        fsType = "unionfs";
        device = lib.concatStringsSep ":" [
          "${writableLayer}"
          "${readOnlySource}"
        ];
        depends = [
          "${writableLayer}"
          "${readOnlySource}"
          "/squash"
        ];
      };
    };

  config = {
    assertions = [
      {
        # Syslinux (and isolinux) only supports x86-based architectures.
        assertion = config.isoImage.makeBiosBootable -> pkgs.stdenv.hostPlatform.isx86;
        message = "BIOS boot is only supported on x86-based architectures.";
      }
      {
        assertion = !(lib.stringLength config.isoImage.volumeID > 32);
        # https://wiki.osdev.org/ISO_9660#The_Primary_Volume_Descriptor
        # Volume Identifier can only be 32 bytes
        message =
          let
            length = lib.stringLength config.isoImage.volumeID;
            howmany = toString length;
            toomany = toString (length - 32);
          in
          "isoImage.volumeID ${config.isoImage.volumeID} is ${howmany} characters. That is ${toomany} characters longer than the limit of 32.";
      }
      (
        let
          badSpecs = lib.filterAttrs (
            specName: specCfg: specCfg.configuration.isoImage.volumeID != config.isoImage.volumeID
          ) config.specialisation;
        in
        {
          assertion = badSpecs == { };
          message = ''
            All specialisations must use the same 'isoImage.volumeID'.

            Specialisations with different volumeIDs:

            ${lib.concatMapStringsSep "\n" (specName: ''
              - ${specName}
            '') (builtins.attrNames badSpecs)}
          '';
        }
      )
    ];

    boot = {
      # Don't build the GRUB menu builder script, since we don't need it
      # here and it causes a cyclic dependency.
      copyKernelToBoot = lib.mkOverride 10 true;
      loader.stand-freebsd.symlinkBootLoader = lib.mkOverride 10 false;
      loader.stand-freebsd.localVariables = {
        loader_brand = "install";
      };
      # bootspec.enable = false;
      loader.label = lib.mkOverride 10 "${config.isoImage.prependToMenuLabel} ${config.system.nixos.distroName} ${config.system.nixos.codeName} ${config.system.nixos.label} ${builtins.toString config.isoImage.configurationName} (${pkgs.freebsd.versionData.version}) ${config.isoImage.appendToMenuLabel}";
      # init needs to be on the rootfs... let's push it onto a memory disk and pivot off of that
      initmd = {
        enable = true;
        pivotFileSystems = [
          "/nix/store"
        ];
      };
    };

    # environment.systemPackages = [
    #   grubPkgs.grub2
    # ] ++ lib.optional (config.isoImage.makeBiosBootable) pkgs.syslinux;
    # system.extraDependencies = [ grubPkgs.grub2_efi ];

    # In stage 1 of the boot, mount the CD as the root FS by label so
    # that we don't need to know its device.  We pass the label of the
    # root filesystem on the kernel command line, rather than in
    # `fileSystems' below.  This allows CD-to-USB converters such as
    # UNetbootin to rewrite the kernel command line to pass the label or
    # UUID of the USB stick.  It would be nicer to write
    # `root=/dev/disk/by-label/...' here, but UNetbootin doesn't
    # recognise that.
    # boot.kernelParams = [
    #   "boot.shell_on_fail"
    #   "root=LABEL=${config.isoImage.volumeID}"
    # ]; # TODO: fix kernel params

    fileSystems = lib.mkOverride 10 config.lib.isoFileSystems;

    # Closures to be copied to the Nix store on the CD, namely the init
    # script and the top-level system configuration directory.
    isoImage.storeContents = [
      config.system.build.toplevel
    ]
    ++ lib.optional config.isoImage.includeSystemBuildDependencies config.system.build.toplevel.drvPath;

    # Individual files to be included on the CD, outside of the Nix
    # store on the CD.
    isoImage.contents =
      let
        cfgFiles =
          cfg:
          lib.optionals cfg.isoImage.showConfiguration [
            # {
            #   # source = cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile;
            #   # target = "/boot/" + cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile;
            #   source = builtins.dirOf cfg.boot.kernel.imagePath;
            #   target = "/boot/kernel/kernel";
            #   # target = "/boot/" + cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile;
            # }
            # { # TODO: Determine if initramfs is needed
            #   source = cfg.system.build.initialRamdisk + "/" + cfg.system.boot.loader.initrdFile;
            #   target = "/boot/" + cfg.system.build.initialRamdisk + "/" + cfg.system.boot.loader.initrdFile;
            # }
          ]
          ++ lib.concatLists (
            lib.mapAttrsToList (_: { configuration, ... }: cfgFiles configuration) cfg.specialisation
          );
      in
      [
        {
          source = pkgs.writeText "version" config.system.nixos.label;
          target = "/version.txt";
        }
      ]
      ++ lib.unique (cfgFiles config)
      ++ lib.optionals (config.isoImage.makeBiosBootable) [
        {
          source = config.isoImage.splashImage;
          target = "/boot/background.png";
        }
        # {
        #   source = pkgs.writeText "isolinux.cfg" isolinuxCfg;
        #   target = "/boot/isolinux.cfg";
        # }
        {
          source = "${pkgs.freebsd.stand-efi}/bin"; # TODO: stand-cdboot ?¿
          target = "/isoloader";
        } # TODO: freebsd cdloader
      ]
      ++ lib.optionals config.isoImage.makeEfiBootable [
        {
          source = efiImg;
          target = "/boot/efi.img";
        }
        {
          source = config.isoImage.efiSplashImage;
          target = "/boot/efi/boot/efi-background.png";
        }
      ]
      # TODO: Implement memtest
      # ++ lib.optionals (config.boot.loader.grub.memtest86.enable && config.isoImage.makeBiosBootable) [
      #   {
      #     source = "${pkgs.memtest86plus}/memtest.bin";
      #     target = "/boot/memtest.bin";
      #   }
      # ]
      ++ lib.optionals (config.isoImage.grubTheme != null) [
        {
          source = config.isoImage.grubTheme;
          target = "/boot/EFI/BOOT/grub-theme";
        }
      ]
      ++ lib.optionals (config.isoImage.makeBiosBootable || config.isoImage.makeEfiBootable) [
        {
          source = "${espContents}/nixos";
          target = "/boot/nixos";
        }
        {
          source = "${espContents}/boot";
          target = "/boot";
        }
      ];

    boot.loader.timeout = 10;

    boot.kernelEnvironment."kern.module_path" = lib.mkOverride 10 "/iso/boot/nixos/default/kernel";

    # Create the ISO image.
    image.extension = if config.isoImage.compressImage then "iso.xz" else "iso";
    image.filePath = "iso/${config.image.fileName}";
    image.baseName = "nixbsd${
      lib.optionalString (config.isoImage.edition != "") "-${config.isoImage.edition}"
    }-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
    system.build.image = config.system.build.isoImage;
    system.build.isoImage = pkgs.callPackage ../../lib/make-cd9660-image.nix (
      {
        inherit (config.isoImage)
          compressImage
          volumeID
          contents
          ;

        squashfsContents = config.isoImage.storeContents;

        isoName = config.image.fileName;
        bootable = config.isoImage.makeBiosBootable;
        # bootImage = "/efiloader/loader.efi"; # TODO: FIx this to legacy cdboot # "/isolinux/isolinux.bin";
      }
      // lib.optionalAttrs (config.isoImage.makeUsbBootable && config.isoImage.makeBiosBootable) {
        usbBootable = true;
        isohybridMbrImage = "${pkgs.syslinux}/share/syslinux/isohdpfx.bin";
      }
      // lib.optionalAttrs config.isoImage.makeEfiBootable {
        efiBootable = true;
        efiBootImage = "boot/efi.img";
      }
    );

    # TODO: adapt using boot.postMountCommands
    # boot.postBootCommands = ''
    #   # After booting, register the contents of the Nix store on the
    #   # CD in the Nix database in the tmpfs.
    #   ${config.nix.package.out}/bin/nix-store --load-db < /nix/store/nix-path-registration

    #   # nixos-rebuild also requires a "system" profile and an
    #   # /etc/NIXOS tag.
    #   touch /etc/NIXOS
    #   ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
    # '';

    # Add vfat support to the initrd to enable people to copy the
    # contents of the CD to a bootable USB stick.
    boot.supportedFilesystems = [ "vfat" ]; # TODO: ensure working
  };
}
