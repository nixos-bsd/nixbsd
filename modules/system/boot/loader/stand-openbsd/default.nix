{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.boot.loader.stand-openbsd;
  builder = import ./stand-conf-builder.nix {
    inherit pkgs;
    stand-efi = pkgs.openbsd.stand;
  };
  populateBuilder = import ./stand-conf-builder.nix {
    pkgs = pkgs.buildPackages;
    stand-efi = pkgs.openbsd.stand;
  };
  builderArgs = "-c";
in
{
  options = {
    boot.loader.stand-openbsd = {
      enable = mkEnableOption (''
        Use the OpenBSD boot loader.
      '');
    };
  };

  config = mkIf cfg.enable {
    system.build.installBootLoader = "${builder} ${builderArgs}";
    system.boot.loader.id = "stand-openbsd";
    boot.loader.bootContents = pkgs.runCommand "bootDerivation" { } ''
      mkdir -p $out
      ${populateBuilder} ${builderArgs} ${config.system.build.toplevel} -d $out -g 0
    '';
    boot.loader.espContents = pkgs.runCommand "espDerivation" { } ''
      mkdir -p $out/efi/boot
      cp ${pkgs.openbsd.stand}/bin/BOOTX64.EFI $out/efi/boot/BOOTX64.EFI
    '';
  };
}
