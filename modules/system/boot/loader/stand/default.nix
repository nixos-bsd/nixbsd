{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.boot.loader.stand;
  builder = import ./stand-conf-builder.nix {
    inherit pkgs;
    inherit (pkgs.freebsd) stand-efi;
  };
  populateBuilder = import ./stand-conf-builder.nix {
    pkgs = pkgs.buildPackages;
    inherit (pkgs.freebsd) stand-efi;
  };
  #timeoutStr = if config.boot.loader.timeout == null then "-1" else toString config.boot.loader.timeout;
  timeoutStr = "-1";
  builderArgs =
    "-g ${builtins.toString cfg.configurationLimit} -t ${timeoutStr} -c";
in {
  options = {
    boot.loader.stand = {
      enable = mkEnableOption (''
        Use the FreeBSD boot loader.
      '');

      configurationLimit = mkOption {
        default = 20;
        example = 10;
        type = types.int;
        description = ''
          Maximum number of configurations in the boot menu.
        '';
      };

      populateCmd = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          Contains the builder command used to populate an image,
          honoring all options except the `-c <path-to-default-configuration>`
          argument.
          Useful to have for sdImage.populateRootCommands
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    system.build.installBootLoader = "${builder} ${builderArgs}";
    system.boot.loader.id = "stand";
    boot.loader.stand.populateCmd = "${populateBuilder} ${builderArgs}";

    boot.kernelEnvironment = mkIf (config.fileSystems ? "/")
      (let fs = config.fileSystems."/";
      in {
        "vfs.root.mountfrom" = "${fs.fsType}:${fs.device}";
        "vfs.root.mountfrom.options" = concatStringsSep "," fs.options;
      });
  };
}
