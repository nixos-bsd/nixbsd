{ lib, config, pkgs, ... }: with lib; let
  system = derivation {
    system = pkgs.stdenv.buildPlatform.system;
    name = "nixbsd-${config.system.label}";
    builder = pkgs.stdenv.shell;
    args = [./toplevel-builder.sh];
    activate = config.system.activationScripts.script;
    inherit (config.system) kernel init initShell bootLoader bootFiles label;
    PATH = "${lib.getBin pkgs.buildPackages.coreutils}/bin";
  };

in {
  options = {
    system.toplevel = mkOption {
      type = types.package;
      readOnly = true;
    };

    system.kernel = mkOption {
      type = types.package;
      default = pkgs.freebsd.sys;
    };

    system.bootLoader = mkOption {
      type = types.package;
      default = pkgs.freebsd.stand-efi;
    };

    system.bootFiles = mkOption {
      default = ["bin/loader.efi" "bin/lua" "bin/defaults"];
    };

    #initShell = mkOption {
    #  type = types.package;
    #  default = pkgs.writeShellScript "init" ''
    #    export PATH=${lib.makeBinPath (with pkgs; [bash coreutils vim])}
    #    exec bash -l
    #  '';
    #};

    system.init = mkOption {
      type = types.str;
      default = "${pkgs.freebsd.init}/bin/init";
    };

    system.initShell = mkOption {
      type = types.str;
      default = "${pkgs.bash}/bin/bash";
    };

    system.label = mkOption {
      type = types.str;
      default = "default";
    };
  };

  config = {
    system.toplevel = system;
  };
}
