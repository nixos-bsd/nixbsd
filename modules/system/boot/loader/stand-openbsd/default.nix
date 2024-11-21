{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.boot.loader.stand-openbsd;
  builder = import ./stand-conf-builder.nix {
    inherit pkgs;
    inherit (pkgs.openbsd) stand;
  };
  populateBuilder = import ./stand-conf-builder.nix {
    pkgs = pkgs.buildPackages;
    inherit (pkgs.openbsd) stand;
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
    #system.boot.loader.id = "stand-openbsd";
    boot.loader.espDerivation = pkgs.runCommand "espDerivation" {} ''
      mkdir -p $out
      ${populateBuilder} ${builderArgs} ${config.system.build.toplevel} -d $out -g 0
    '';
  };
}
