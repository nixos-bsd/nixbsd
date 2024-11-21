{ config, pkgs, lib, ... }:
with lib;
let cfg = config.boot.kernel;
in {
  options = {
    boot.kernel.enable = mkEnableOption (
      "the kernel (sys). This can be disabled for jails where the host kernel is used")
      // {
        default = true;
      };

    boot.kernel.package = mkOption {
      default = pkgs.freebsd.sys;
      type = types.package;
      description = ''
        The package used for the kernel. This is just the derivation
        with the kernel and doesn't include out-of-tree modules.
      '';
    };

    boot.kernel.isFreeBSD = mkOption {
      default = cfg.package.meta.platforms == platforms.freebsd;
      type = types.bool;
      readOnly = true;
      description = ''
        Whether this system runs a FreeBSD kernel.
      '';
    };

    boot.kernel.isOpenBSD = mkOption {
      default = cfg.package.meta.platforms == platforms.openbsd;
      type = types.bool;
      readOnly = true;
      description = ''
        Whether this system runs an OpenBSD kernel.
      '';
    };

    boot.kernel.flavor = mkOption {
      default = if cfg.isFreeBSD then "freebsd"
        else if cfg.isOpenBSD then "openbsd"
        else throw "Couldn't detect known kernel; need either freebsd.sys or openbsd.sys";
      type = types.str;
      readOnly = true;
      description = ''
        A string indicating the kind of kernel being booted. One of:

        - "freebsd"
        - "openbsd"
      '';
    };

    boot.extraModulePackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example =
        literalExpression "with pkgs.freebsd; [ drm-kmod drm-kmod-firmware ]";
      description =
        "A list of additional packages supplying kernel modules.";
    };

    system.moduleEnvironment = mkOption {
      type = types.package;
      internal = true;
      description = ''
        Linked environment of the kernel and all module packages, so that they can be linked into
        kernel-modules in the toplevel derivation.
      '';
    };

    boot.kernel.imagePath = mkOption {
      type = types.path;
      readOnly = true;
      default = {
        freebsd = "${config.system.moduleEnvironment}/kernel/kernel";
        openbsd = "${cfg.package}/bsd";
      }.${cfg.flavor};
    };

    boot.kernel.modulesPath = mkOption {
      type = types.path;
      readOnly = true;
      default = {
        freebsd = "${config.system.moduleEnvironment}/kernel";
        openbsd = "/not-supported";
      }.${cfg.flavor};
    };

    boot.kernelEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        boot_serial = "YES";
        "kern.maxusers" = "16";
      };
      description = ''
        Environment set for kernel, similar to kernel arguments on Linux.
        All variables are key=value, so using an attrset here.
      '';
    };
  };

  config = mkIf cfg.enable {
    system.build = { inherit (config.boot) kernel; };
    system.moduleEnvironment = mkIf cfg.isFreeBSD (pkgs.buildEnv {
      name = "sys-with-modules";
      paths = [ cfg.package ] ++ config.boot.extraModulePackages;
      pathsToLink = [ "/kernel" ];

      postBuild = ''
        ${pkgs.buildPackages.freebsd.kldxref}/bin/kldxref $out/kernel
      '';
    });

    system.systemBuilderCommands = ''
      if [ ! -f ${cfg.imagePath} ]; then
        echo "The bootloader cannot find the proper kernel image."
        echo "(expecting ${cfg.imagePath})"
        false
      fi

      ln -s ${cfg.imagePath} $out/kernel
      test -e ${cfg.modulesPath} && ln -s ${cfg.modulesPath} $out/kernel-modules || true
    '';

    boot.kernelEnvironment = mkIf cfg.isFreeBSD {
      module_path = cfg.modulesPath;
      init_shell = config.environment.binsh;
    };
  };
}
