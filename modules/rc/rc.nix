{ pkgs, config, lib, ...}: with lib;
let
  cfg = config.rc;
  mkRcScript = {
    name
  , command
  , shell
  , rc
  }: pkgs.stdenv.writeTextFile {
    name = "${name}-rc";
    text = ''
      #!${shell}${shell.shellPath or ""}

      . ${rc}/etc/rc.subr

      name="${name}"
      rcvar="${name}_enabled"
      command="${command}"

      load_rc_config ${name}
      run_rc_command "$1"
    '';
  };
  mkRcDir = scriptCfg: pkgs.runCommand "rc.d" { scripts = map mkRcScript scriptCfg; } ''
    mkdir -p $out
    ln -s $scripts $out
  '';
in {
  options.rc.enabled = (mkEnableOption "rc");
  options.rc.entries = {
    type = listOf types.submodule {
      options.name = mkOption {
        type = types.strMatching "[_a-zA-Z][_a-zA-Z0-9]*";
        description = "The name of the service. Gets used as a variable name.";
      };

      options.command = mkOption {
        type = types.storePath;
        description = "The executable to run to start this service";
      };

      options.shell = mkOption {
        type = types.shellPackage;
        description = "The shell with which to run the rc-script when invoked directly. Probably don't change this.";
        default = pkgs.bash;
      };

      options.rc = mkOption {
        type = types.pkg;
        description = "The rc derivation from which to source internal scripts during rc-script execution. Probably don't change this.";
        default = pkgs.freebsd.rc;
      };
    };
  };

  config = mkIf cfg.enabled {
    # TODO whatever the hell needs to be done to hook rc up to init
    # TODO whatever the hell needs to be done to hook rc.d up to rc
    # TODO add rc.d to etc
  };
}
