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

  config = mkIf config.boot.kernel.enable (let
    kernelPath = "${cfg.package}/${config.system.boot.loader.kernelFile}";
    modulesPath = "${cfg.package}/${config.system.boot.loader.modulesPath}";
  in {
    system.build = { inherit (config.boot) kernel; };

    system.systemBuilderCommands = ''
      if [ ! -f ${kernelPath} ]; then
        echo "The bootloader cannot find the proper kernel image."
        echo "(expecting ${kernelPath})"
        false
      fi

      ln -s ${kernelPath} $out/kernel
      ln -s ${modulesPath} $out/kernel-modules
    '';

    boot.kernelEnvironment = {
      module_path = modulesPath;
      init_shell = config.environment.binsh;
    };
  });
}
