{ lib, config, nixpkgs, ... }: with lib; let
  pkgs = config.targetPackages;
  system = derivation {
    system = nixpkgs.stdenv.buildPlatform.system;
    name = "nixbsd-${config.system.label}";
    builder = nixpkgs.stdenv.shell;
    args = [./toplevel-builder.sh];
    inherit (config.system) kernel init initShell bootLoader bootFiles label activate;
    PATH = "${lib.getBin nixpkgs.coreutils}/bin";
  };

in {
  options.system.target = mkOption {
    type = types.str;
    default = "x86_64-freebsd14";
  };

  options.targetPackages = mkOption {
    readOnly = true;
  };

  options.system.toplevel = mkOption {
    type = types.package;
    readOnly = true;
  };

  options.system.kernel = mkOption {
    type = types.package;
    default = pkgs.freebsd.sys;
  };

  options.system.bootLoader = mkOption {
    type = types.package;
    default = pkgs.freebsd.stand-efi;
  };

  options.system.bootFiles = mkOption {
    default = ["bin/loader.efi" "bin/lua" "bin/defaults"];
  };

  #options.initShell = mkOption {
  #  type = types.package;
  #  default = pkgs.writeShellScript "init" ''
  #    export PATH=${lib.makeBinPath (with pkgs; [bash coreutils vim])}
  #    exec bash -l
  #  '';
  #};

  options.system.init = mkOption {
    type = types.str;
    default = "${pkgs.freebsd.init}/bin/init";
  };

  options.system.initShell = mkOption {
    type = types.str;
    default = "${pkgs.bash}/bin/bash";
  };

  options.system.label = mkOption {
    type = types.str;
    default = "default";
  };

  options.system.activate = mkOption {
    type = types.str;
  };

  config.system.toplevel = system;
  config.targetPackages = nixpkgs.pkgsCross.${config.system.target};
}
