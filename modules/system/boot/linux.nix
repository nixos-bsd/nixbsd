{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.boot.linux;
  systems = {
    x86_64-freebsd = {
      compatSystem = "x86_64-linux";
      compatSystem32 = "i686-linux";
    };
    i686-freebsd = {
      compatSystem = "i686-linux";

    };
    aarch64-freebsd = { compatSystem = "aarch64-freebsd"; };
  };
  system = systems.${pkgs.hostPlatform.system} or (throw
    "Unsupported host system for Linux emulation");
in {
  options = {
    boot.linux = {
      enable = mkEnableOption "Linux emulation";
      enable32Bit = mkEnableOption "32-bit support on x86_64";

      mountLinux = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Mount linux filesystems (e.g. linprocfs, linsysfs)
        '';
      };

      setFallback = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Fallback to Linux
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = cfg.enable32Bit -> system ? compatsSystem32;
      message = ''
        32-bit emulation is not supported on this platform.
      '';
    }];

    nix.settings.extra-platforms = [ system.compatSystem ]
      ++ lib.optional cfg.enable32Bit system.compatSystem32;

    rc.services.linux = {
      description = "Linux user-mode emulation";
      provides = "linux";
      requires = [ ];
      keywordNojail = true;
      binDeps = with pkgs.freebsd; [ kldload kldstat sysctl mount ];
      commands.stop = ":";
      commands.start = optionalString pkgs.hostPlatform.is64bit ''
        load_kld -e linux64elf linux64
      '' + optionalString (cfg.enable32Bit || pkgs.hostPlatform.is32bit) ''
        load_kld -e linuxelf linux
      '' + ''
        # We want linux to be ready immediately after this service,
        # not after the late sysctl set, so set sysctls manually here
        mkdir -p /etc/compat/linux
        sysctl -w compat.linux.emul_path=/etc/compat/linux
      '' + lib.optionalString
        (cfg.setFallback && (cfg.enable32Bit || pkgs.hostPlatform.is32bit)) ''
          sysctl -w kern.elf32.fallback_brand=3
        ''
        + lib.optionalString (cfg.setFallback && pkgs.hostPlatform.is64bit) ''
          sysctl -w kern.elf64.fallback_brand=3
        '' + ''
          # the upstream rc script says modules are required even if mounts aren't done
          load_kld -m pty pty
          load_kld -m fdescfs fdescfs
          load_kld -m linprocfs linprocfs
          load_kld -m linsysfs linsysfs
        '' + lib.optionalString cfg.mountLinux ''
          # Again, we don't want to rely on mount ordering, just mount here
          linux_mount linprocfs /etc/compat/linux/proc -o nocover
          linux_mount linsysfs /etc/compat/linux/sys -o nocover
          linux_mount devfs /etc/compat/linux/dev -o nocover
          linux_mount fdescfs /etc/compat/linux/dev/fd -o nocover,linrdlnk
          linux_mount tmpfs /etc/compat/linux/dev/shm -o nocover,mode=1777
        '';

      # Stolen directly from freebsd libexec/rc/rc.d/linux
      extraConfig = ''
        linux_mount() {
          local _fs _mount_point
          _fs="$1"
          _mount_point="$2"
          shift 2
          if ! mount | grep -q "^$_fs on $_mount_point ("; then
            mkdir -p "$_mount_point"
            mount "$@" -t "$_fs" "$_fs" "$_mount_point"
          fi
        }
      '';

      # TODO: figure out LOCALE_ARCHIVE
    };
  };
}
