{ config, pkgs, lib, ... }:
with lib;
let cfg = config.boot.kernel;
in {
  options = {
    boot.kernel.enable = mkEnableOption (
      "the FreeBSD kernel (sys). This can be disabled for jails where the host kernel is used")
      // {
        default = true;
      };

    boot.kernel.package = mkOption {
      default = {
        freebsd = pkgs.freebsd.sys;
        openbsd = pkgs.openbsd.sys;
      }.${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      defaultText = literalExpression ''
        {
          freebsd = pkgs.freebsd.sys;
          openbsd = pkgs.openbsd.sys;
        }.''${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      '';
      type = types.package;
      description = ''
        The package used for the kernel. This is just the derivation
        with the kernel and doesn't include out-of-tree modules.
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
      }.${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      defaultText = literalExpression ''
        {
          freebsd = "''${config.system.moduleEnvironment}/kernel/kernel";
          openbsd = "''${cfg.package}/bsd";
        }.''${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      '';
      description = "Path to the BSD kernel, called `bsd` or `kernel`";
    };

    boot.kernel.modulesPath = mkOption {
      type = types.path;
      readOnly = true;
      default = {
        freebsd = "${config.system.moduleEnvironment}/kernel";
        openbsd = "/not-supported";
      }.${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      defaultText = literalExpression ''
        {
          freebsd = "''${config.system.moduleEnvironment}/kernel";
          openbsd = "/not-supported";
        }.''${pkgs.stdenv.hostPlatform.parsed.kernel.name};
      '';
      description = "Path to the modules directory, only applies on FreeBSD";
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
    system.installerDependencies = [
      pkgs.freebsd.kldxref
    ];
    system.build = { inherit (config.boot) kernel; };
    system.moduleEnvironment = mkIf pkgs.stdenv.hostPlatform.isFreeBSD (pkgs.buildEnv {
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

    boot.kernelEnvironment = mkIf pkgs.stdenv.hostPlatform.isFreeBSD {
      module_path = cfg.modulesPath;
      init_shell = config.environment.binsh;
    };
  };
}
