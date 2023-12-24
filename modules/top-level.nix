{ lib, config, nixpkgs, ... }: with lib; let
  pkgs = config.targetPackages;
  system = derivation {
    system = nixpkgs.stdenv.buildPlatform.system;
    name = "nixbsd-${config.label}";
    builder = nixpkgs.stdenv.shell;
    args = [./toplevel-builder.sh];
    inherit (config) kernel init bootLoader bootFiles label;
    PATH = "${lib.getBin nixpkgs.coreutils}/bin";
  };

in {
  options.target = mkOption {
    type = types.str;
    default = "x86_64-freebsd14";
  };

  options.targetPackages = mkOption {
    readOnly = true;
  };

  options.toplevel = mkOption {
    type = types.package;
    readOnly = true;
  };

  options.kernel = mkOption {
    type = types.package;
    default = pkgs.freebsd.sys;
  };

  options.bootLoader = mkOption {
    type = types.package;
    default = pkgs.freebsd.stand-efi;
  };

  options.bootFiles = mkOption {
    default = ["bin/loader.efi" "bin/lua" "bin/defaults"];
  };

  options.init = mkOption {
    type = types.package;
    default = pkgs.writeShellScript "init" ''
      export PATH=${lib.concatStringsSep ":" (with pkgs; [bash coreutils vim])}
      exec bash -l
    '';
  };

  options.label = mkOption {
    type = types.str;
    default = "default";
  };

  config.toplevel = system;
  config.targetPackages = nixpkgs.pkgsCross.${config.target};
}
