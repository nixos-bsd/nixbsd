# This module creates a bootable ISO 9660 image for NixBSD.
# It produces an EFI-bootable ISO with the Nix store embedded directly
# on the ISO filesystem (uncompressed).
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.isoImage;

  espContents = config.boot.loader.espContents;
  toplevel = config.system.build.toplevel;

  # The espContents has broken relative symlinks for kernel modules.
  # Create a resolved copy with real files for use on the ISO and EFI image.
  resolvedEspContents = pkgs.runCommand "esp-resolved" {
    nativeBuildInputs = [ pkgs.rsync ];
    # Ensure the kernel closure is available in the sandbox
    inherit toplevel;
  } ''
    mkdir -p $out

    # Copy the ESP contents (preserving broken symlinks initially)
    cp -a ${espContents}/* $out/ 2>/dev/null || true

    # Make everything writable so we can fix symlinks
    chmod -R u+w $out

    # Find and fix all broken symlinks by resolving relative targets against /nix/store
    find $out -type l | while read -r link; do
      target=$(readlink "$link")
      if [[ "$target" == ../../* ]] && [ ! -e "$link" ]; then
        # These symlinks were meant to resolve from /nix/store/<hash>/<subdir>/
        # Extract the store-relative path (strip leading ../../)
        store_relative="''${target#../../}"
        abs_target="/nix/store/$store_relative"
        if [ -e "$abs_target" ]; then
          rm "$link"
          cp "$abs_target" "$link"
        else
          echo "WARNING: Cannot resolve symlink $link -> $target (tried $abs_target)"
          rm "$link"
        fi
      elif [ ! -e "$link" ]; then
        echo "WARNING: Broken symlink $link -> $target"
        rm "$link"
      fi
    done
  '';

  # Build the EFI boot image (FAT filesystem) for El-Torito booting
  efiBootImage = pkgs.callPackage ../../../lib/make-partition-image.nix {
    inherit pkgs lib;
    label = "EFIBOOT";
    filesystem = "efi";
    contents = [
      {
        target = "/";
        source = resolvedEspContents;
      }
    ];
    totalSize = "256m";
  };

  # The full set of store paths to include on the ISO
  storeContents = [ config.system.build.toplevel ];

  # Additional files to place on the ISO (outside the Nix store)
  isoContents =
    [
      # EFI boot image must be at a known path on the ISO for El-Torito
      {
        source = "${efiBootImage}";
        target = "/boot/efi.img";
      }
      # Boot loader files (lua scripts, defaults, config) on the ISO root
      # so that loader.efi can find them when it switches currdev to cd0:
      {
        source = "${resolvedEspContents}/boot";
        target = "/boot";
      }
      # Kernel and initmd files referenced by the boot config
      {
        source = "${resolvedEspContents}/nixos";
        target = "/nixos";
      }
      # Include the toplevel system link for easy reference
      {
        source = config.system.build.toplevel;
        target = "/run/current-system";
      }
    ]
    ++ cfg.contents;

in
{
  options = {
    isoImage = {
      isoName = mkOption {
        default = "${config.system.name}.iso";
        type = types.str;
        description = ''
          Name of the generated ISO image file.
        '';
      };

      volumeID = mkOption {
        default = "NIXBSD_ISO";
        type = types.str;
        description = ''
          The volume ID of the ISO image. Limited to 32 characters.
        '';
      };

      contents = mkOption {
        default = [ ];
        type = types.listOf (
          types.submodule {
            options = {
              source = mkOption { type = types.path; };
              target = mkOption { type = types.str; };
            };
          }
        );
        description = ''
          Additional files/directories to place on the ISO filesystem.
        '';
      };

      storeContents = mkOption {
        default = [ ];
        type = types.listOf types.package;
        description = ''
          Additional store paths whose closures should be included on the ISO.
        '';
      };

      compressImage = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to compress the resulting ISO image with xz.
        '';
      };

      includeStoreRegistration = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether to include a Nix path registration file on the ISO,
          allowing the live system to use `nix-store --load-db` to register paths.
        '';
      };
    };
  };

  config = {
    # The ISO image derivation
    system.build.isoImage = pkgs.callPackage ../../../lib/make-cd9660-image.nix {
      inherit pkgs lib;

      isoName = cfg.isoName;
      volumeID = cfg.volumeID;
      compressImage = cfg.compressImage;
      inherit (pkgs) zstd;

      # EFI boot configuration
      efiBootable = true;
      efiBootImage = "/boot/efi.img";

      # Contents on the ISO filesystem
      contents = isoContents;

      # Store paths to embed (full closure copied to /nix/store on ISO)
      storeContents = storeContents ++ cfg.storeContents;
      storeRegistration = cfg.includeStoreRegistration;

      # We don't use the squashfs/compressed path for now
      squashfsContents = [ ];
    };
  };
}
