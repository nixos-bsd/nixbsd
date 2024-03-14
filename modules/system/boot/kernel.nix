{ config, pkgs, lib, ... }:
with lib;
let cfg = config.boot.kernel;
in {
  options = {
    boot.kernel.enable = mkEnableOption (lib.mdDoc
      "the FreeBSD kernel (sys). This can be disabled for jails where the host kernel is used")
      // {
        default = true;
      };

    boot.kernel.package = mkOption {
      default = pkgs.freebsd.sys;
      type = types.package;
      description = lib.mdDoc ''
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
        lib.mdDoc "A list of additional packages supplying kernel modules.";
    };

    system.moduleEnvironment = mkOption {
      type = types.package;
      internal = true;
      description = lib.mdDoc ''
        Linked environment of the kernel and all module packages, so that they can be linked into
        kernel-modules in the toplevel derivation.
      '';
    };

    boot.kernelEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        boot_serial = "YES";
        "kern.maxusers" = "16";
      };
      description = lib.mdDoc ''
        Environment set for kernel, similar to kernel arguments on Linux.
        All variables are key=value, so using an attrset here.
      '';
    };
  };

  config = mkIf cfg.enable (let
    kernelPath = "${config.system.moduleEnvironment}/kernel/kernel";
    modulePath = "${config.system.moduleEnvironment}/kernel";
  in {
    system.build = { inherit (config.boot) kernel; };
    system.moduleEnvironment = pkgs.buildEnv {
      name = "sys-with-modules";
      paths = [ cfg.package ] ++ config.boot.extraModulePackages;
      pathsToLink = [ "/kernel" ];

      # No way to run kldxref with compat
      postBuild = lib.optionalString pkgs.stdenv.buildPlatform.isFreeBSD ''
        ${pkgs.freebsd.kldxref}/bin/kldxref $out/kernel
      '';
    };

    system.systemBuilderCommands = ''
      if [ ! -f ${kernelPath} ]; then
        echo "The bootloader cannot find the proper kernel image."
        echo "(expecting ${kernelPath})"
        false
      fi

      ln -s ${kernelPath} $out/kernel
      ln -s ${modulePath} $out/kernel-modules
    '';

    boot.kernelEnvironment = {
      module_path = modulePath;
      init_shell = config.environment.binsh;
    };
  });
}
