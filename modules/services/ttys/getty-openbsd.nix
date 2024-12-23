{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.getty;
  gettyTab = "${cfg.package}/etc/gettytab";
  gettyBin = lib.getExe cfg.package;
in {
  options.services.getty = {
    enabled = (mkEnableOption "getty") // { default = true; };
    package = mkPackageOption pkgs [ "openbsd" "getty" ] { };
  };

  config = mkIf cfg.enabled {
    environment.etc.ttys.text = ''
      # name	getty				type	status		comments
      console "${gettyBin} std.9600"   vt220   off secure
      ttyC0   "${gettyBin} std.9600"   vt220   on  secure
      ttyC1   "${gettyBin} std.9600"   vt220   on  secure
      ttyC2   "${gettyBin} std.9600"   vt220   on  secure
      ttyC3   "${gettyBin} std.9600"   vt220   on  secure
      ttyC4   "${gettyBin} std.9600"   vt220   off secure
      ttyC5   "${gettyBin} std.9600"   vt220   on  secure
      ttyC6   "${gettyBin} std.9600"   vt220   off secure
      ttyC7   "${gettyBin} std.9600"   vt220   off secure
      ttyC8   "${gettyBin} std.9600"   vt220   off secure
      ttyC9   "${gettyBin} std.9600"   vt220   off secure
      ttyCa   "${gettyBin} std.9600"   vt220   off secure
      ttyCb   "${gettyBin} std.9600"   vt220   off secure
      tty00   "${gettyBin} std.9600"   unknown off
      tty01   "${gettyBin} std.9600"   unknown off
      tty02   "${gettyBin} std.9600"   unknown off
      tty03   "${gettyBin} std.9600"   unknown off
      tty04   "${gettyBin} std.9600"   unknown off
      tty05   "${gettyBin} std.9600"   unknown off
      tty06   "${gettyBin} std.9600"   unknown off
      tty07   "${gettyBin} std.9600"   unknown off
    '';
    environment.etc.gettytab.source = gettyTab;

    users.classes.default.settings.auth = lib.mkDefault "passwd";

    security.wrappers.login_passwd = {
      setuid = true;
      owner = "root";
      group = "auth";
      permissions = "u+rx,g+rx,o+rx";
      source = "${pkgs.openbsd.login_passwd}/bin/login_passwd";
    };
  };
}
