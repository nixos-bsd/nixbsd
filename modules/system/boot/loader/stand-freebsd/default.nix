{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  loaderSetENV = k: v: ''loader.setenv("${k}","${v}")'';
  localScript = builtins.toFile "loader.local.lua" ''
    -- Setting variables from Nix boot.loader.stand-freebsd.localVariables
    ${lib.concatMapAttrsStringSep "\n" loaderSetENV cfg.localVariables}

    -- BEGIN USER SCRIPT
    ${cfg.bootLUAScript}
    -- END USER SCRIPT
  '';

  cfg = config.boot.loader.stand-freebsd;
  builder = import ./stand-conf-builder.nix {
    inherit pkgs;
    inherit (pkgs.freebsd) stand-efi;
    inherit localScript;
  };
  populateBuilder = import ./stand-conf-builder.nix {
    pkgs = pkgs.buildPackages;
    inherit (pkgs.freebsd) stand-efi;
    inherit localScript;
  };

  timeoutStr = if config.boot.loader.timeout == null then "-1" else toString config.boot.loader.timeout;

  findMount = path: if config.fileSystems?"${path}" then path
    else if path == "/" then path
    else findMount (dirOf path);
  nixStorePath = if config.readOnlyNixStore.enable then config.readOnlyNixStore.readOnlySource else "/nix/store";
  nixStoreMount = findMount nixStorePath;
  nixStoreFs = config.fileSystems.${nixStoreMount};

  mkDevice =
    fs:
    if fs.fsType == "zfs" then
      "zfs:${fs.device}"
    else if
      lib.hasPrefix "/dev/iso9660/" root.device # then "label:${lib.strings.substring 14 (-1) root.device}"
    then
      "cd9660:${root.device}" # mounting iso image as root
    else if lib.hasPrefix "/dev/gpt/" fs.device then
      "label:${lib.strings.substring 9 (-1) fs.device}"
    else if lib.hasPrefix "/dev/" fs.device && !(lib.hasPrefix "/dev/ufs" fs.device) then
      lib.strings.substring 5 (-1) fs.device
    else
      throw "Can't tell the bootloader how to find ${fs.fsType} ${fs.device}. Try a zfs dataset or /dev/gpt/*.";

  nixStoreDevice = if config.boot.copyKernelToBoot then "notused" else mkDevice nixStoreFs;
  nixStoreSuffix = if config.boot.copyKernelToBoot then "/not/used" else lib.strings.removePrefix nixStoreMount nixStorePath;
  copyKernelsArg = lib.optionalString config.boot.copyKernelToBoot "-C";
  symlinkBootArg = lib.optionalString cfg.symlinkBootLoader "-L";
  builderArgs = "-g ${builtins.toString cfg.configurationLimit} -t ${timeoutStr} -n ${nixStoreDevice} -N '${nixStoreSuffix}' ${copyKernelsArg} ${symlinkBootArg} -c";
in
{
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

      localVariables = mkOption {
        default = { };
        type = types.attrsOf types.str;

        description = ''
          Additional variables passed to loader via /boot/lua/local.lua
        '';
      };

      bootLUAScript = mkOption {
        default = "";
        type = types.lines;

        description = ''
          Script to append at /boot/lua/local.lua
        '';
      };

      symlinkBootLoader = mkOption {
        default = config.virtualisation.netMountBoot or config.virtualisation.vmVariant.virtualisation.netMountBoot or false;
        defaultText = literalExpression "!config.virtualisation.netMountBoot";
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
    boot.loader.espContents = pkgs.runCommand "espDerivation" { } ''
      mkdir -p $out
      ${populateBuilder} ${builderArgs} ${config.system.build.toplevel} -d $out -g 0
    '';

    boot.loader.stand-freebsd.localVariables = lib.mkDefault {
      "loader_brand" = "neexbsd"; # Fancy-ness
      "loader_logo" = "nixorb"; # Fancy-ness
    };

    boot.kernelEnvironment = mkIf (config.fileSystems ? "/") (
      let
        fs = config.fileSystems."/";
      in
      {
        "vfs.root.mountfrom" = "${fs.fsType}:${fs.device}";
        "vfs.root.mountfrom.options" = concatStringsSep "," fs.options;
      }
    );
  };
}
