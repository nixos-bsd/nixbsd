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
        # Serial terminals
        ttyu0	"${gettyBin} 3wire"	vt100	onifconsole secure
        ttyu1	"${gettyBin} 3wire"	vt100	onifconsole secure
        ttyu2	"${gettyBin} 3wire"	vt100	onifconsole secure
        ttyu3	"${gettyBin} 3wire"	vt100	onifconsole secure
        # Dumb console
        dcons	"${gettyBin} std.115200"	vt100	off secure
        # Xen Virtual console
        xc0	"${gettyBin} Pc"		xterm	onifconsole secure
        # RISC-V HTIF console
        rcons	"${gettyBin} std.115200"	vt100	onifconsole secure
      '';
    };
    environment.etc.gettytab.source = gettyTab;
    security.pam.services.login.text = ''
      # auth
      auth		sufficient	pam_self.so		no_warn
      auth		include		system

      # account
      account		requisite	pam_securetty.so
      account		required	pam_nologin.so
      account		include		system

      # session
      session		include		system

      # password
      password	include		system
    '';
    security.wrappers.login = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${pkgs.freebsd.login}/bin/login";
    };
  };
}
