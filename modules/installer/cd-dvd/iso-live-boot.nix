# This module configures a NixBSD system for live booting from an ISO image.
# It sets up:
# - tmpfs as root filesystem
# - initmd (memory disk) for early boot pivot
# - CD-ROM mount for accessing the Nix store on the ISO
# - Read-only Nix store with tmpfs writable overlay
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cdDevice = "/dev/cd0";
  cdMountPoint = "/iso";

  # Match the priority used by readOnlyNixStore in nix-store.nix
  mkVMOverride = lib.mkOverride 10;
in
{
  config = {
    # Filesystem layout for the live ISO.
    # Uses mkVMOverride (priority 10) to match readOnlyNixStore's fileSystems.
    fileSystems = mkVMOverride {
      "/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        noCheck = true;
      };

      ${cdMountPoint} = {
        device = cdDevice;
        fsType = "cd9660";
        options = [ "ro" ];
        noCheck = true;
      };

      "/nix/.ro-store" = {
        device = "${cdMountPoint}/nix/store";
        fsType = "nullfs";
        options = [ "ro" ];
        depends = [ cdMountPoint ];
        noCheck = true;
      };
    };

    # Read-only nix store with writable tmpfs overlay
    readOnlyNixStore = {
      enable = true;
      readOnlySource = "/nix/.ro-store";
      writableTmpfs = true;
    };

    # Boot from memory disk, pivot to mount /nix/store from CD
    boot.initmd = {
      enable = true;
      pivotFileSystems = [ "/nix/store" ];
    };

    # Kernel modules needed for CD-ROM and overlay access
    boot.kernelModules = [ "cd9660" ];

    # Copy kernel to ESP (needed for the EFI boot image on ISO)
    boot.copyKernelToBoot = true;

    # No writable ESP on a CD
    system.build.installBootLoader = mkForce "${pkgs.coreutils}/bin/true";

    # Empty fstab - all filesystems are mounted by init0
    environment.etc."fstab" = mkForce { text = ""; };

    # No-op mountcritlocal since init0 handles all mounts.
    # The default fails when fstab is empty (FreeBSD xargs quirk).
    freebsd.rc.services.mountcritlocal.hooks.start_cmd = mkForce ":";

    # Disable devd (needs persistent /var/log)
    freebsd.rc.conf.devd_enable = mkForce false;

    # Set early_late_divider directly in rc.conf since /etc/defaults/rc.conf
    # may not be accessible through the filesystem layers at rc parse time.
    freebsd.rc.conf.early_late_divider = "FILESYSTEMS";

    # Signal init to re-read /etc/ttys after boot completes.
    # /etc/ttys is created during activation (after init starts), so init
    # needs a HUP to pick it up and spawn gettys.
    freebsd.rc.services.iso_getty_init = {
      description = "Signal init to spawn gettys";
      rcorderSettings = {
        REQUIRE = [ "LOGIN" ];
        KEYWORD = [ "nojail" ];
      };
      hooks.start_cmd = ''
        kill -HUP 1
      '';
    };
    freebsd.rc.conf.iso_getty_init_enable = true;

    # No swap on a live CD
    swapDevices = mkForce [ ];

    # Create required directories early in activation.
    system.activationScripts.iso-early-setup = lib.stringAfter [ "stdio" ] ''
      mkdir -p /etc /var/log /var/run /var/tmp /var/db /var/empty /var/cache
      mkdir -p /var/spool/lock /var/lib/nixos /var/run/dhcpcd
      mkdir -p /run/resolvconf
      mkdir -p /tmp
      chmod 1777 /tmp /var/tmp
    '';

    # Ensure /etc is fully populated. setup-etc.pl creates symlinks from
    # /etc/ -> /etc/static/, but some may not resolve through the
    # unionfs/nullfs/cd9660 layers. Copy missing files directly.
    system.activationScripts.iso-etc-fixup = lib.stringAfter [ "etc" ] ''
      if [ -d /etc/static ]; then
        cd /etc/static
        find . -type f -o -type l | while read -r f; do
          target="/etc/$f"
          if [ ! -e "$target" ]; then
            mkdir -p "$(dirname "$target")"
            cp -a "/etc/static/$f" "$target" 2>/dev/null || true
          fi
        done
        cd /
      fi
    '';
  };
}
