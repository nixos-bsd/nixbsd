{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.boot.loader.stand-freebsd;
  initmd = if config.boot.initmd.enable then config.boot.initmd.image else null;
  builder = import ./stand-conf-builder.nix {
    inherit pkgs initmd;
    inherit (pkgs.freebsd) stand-efi;
  };
  populateBuilder = import ./stand-conf-builder.nix {
    pkgs = pkgs.buildPackages;
    inherit initmd;
    inherit (pkgs.freebsd) stand-efi;
  };
  #timeoutStr = if config.boot.loader.timeout == null then "-1" else toString config.boot.loader.timeout;
  timeoutStr = "-1";
  builderArgs =
    "-g ${builtins.toString cfg.configurationLimit} -t ${timeoutStr} -c";
in {
  options = {
    boot.loader.stand-freebsd = {
      enable = mkOption {
        default = !config.boot.isJail;
        defaultText = literalExpression "!config.boot.isJail";
        type = types.bool;
        description = ''
          Use the FreeBSD bootloader.
        '';
      };

      configurationLimit = mkOption {
        default = 20;
        example = 10;
        type = types.int;
        description = ''
          Maximum number of configurations in the boot menu.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    system.build.installBootLoader = "${builder} ${builderArgs}";
    system.boot.loader.id = "stand-freebsd";
    boot.loader.espContents = pkgs.runCommand "espDerivation" {} ''
      mkdir -p $out
      ${populateBuilder} ${builderArgs} ${config.system.build.toplevel} -d $out -g 0
    '';

    boot.kernelEnvironment = mkIf (config.fileSystems ? "/")
      (let fs = config.fileSystems."/";
      in {
        "vfs.root.mountfrom" = "${fs.fsType}:${fs.device}";
        "vfs.root.mountfrom.options" = concatStringsSep "," fs.options;
      });
  };
}
