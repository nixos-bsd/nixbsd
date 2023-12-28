{ config, lib, pkgs, ... }: with lib;
let
  cfg = config.services.getty;
  gettyBin = "${cfg.package}/bin/getty";
  gettyTab = "${cfg.package}/etc/gettytab";
in
{
  options.services.getty = {
    enabled = (mkEnableOption "getty") // { default = true; };
    package = mkOption {
      type = types.package;
      default = pkgs.freebsd.getty;
    };
  };

  config = mkIf cfg.enabled {
    environment.etc.ttys = {
      text = ''
        # name	getty				type	status		comments
        console	none				unknown	off secure
        #
        ttyv0	"${gettyBin} Pc"		xterm	onifexists secure
        # Virtual terminals
        ttyv1	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv2	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv3	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv4	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv5	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv6	"${gettyBin} Pc"		xterm	onifexists secure
        ttyv7	"${gettyBin} Pc"		xterm	onifexists secure
      '';
    };
    environment.etc.gettytab.source = gettyTab;
  };
}
