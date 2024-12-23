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
    environment.etc."login.conf".text = lib.mkForce ''
      # Default allowed authentication styles
      auth-defaults:auth=passwd,skey:

      # Default allowed authentication styles for authentication type ftp
      auth-ftp-defaults:auth-ftp=passwd:

      #
      # The default values
      # To alter the default authentication types change the line:
      #        :tc=auth-defaults:\
      # to read something like: (enables passwd, "myauth", and activ)
      #        :auth=passwd,myauth,activ:\
      # Any value changed in the daemon class should be reset in default
      # class.
      #
      default:\
              :path=/run/current-system/sw/bin:\
              :umask=022:\
              :datasize-max=1536M:\
              :datasize-cur=1536M:\
              :maxproc-max=256:\
              :maxproc-cur=128:\
              :openfiles-max=1024:\
              :openfiles-cur=512:\
              :stacksize-cur=4M:\
              :localcipher=blowfish,a:\
              :tc=auth-defaults:\
              :tc=auth-ftp-defaults:

      #
      # Settings used by /etc/rc and root
      # This must be set properly for daemons started as root by inetd as well.
      # Be sure to reset these values to system defaults in the default class!
      #
      daemon:\
              :ignorenologin:\
              :datasize=4096M:\
              :maxproc=infinity:\
              :openfiles-max=1024:\
              :openfiles-cur=128:\
              :stacksize-cur=8M:\
              :tc=default:

      #
      # Staff have fewer restrictions and can login even when nologins are set.
      #
      staff:\
              :datasize-cur=1536M:\
              :datasize-max=infinity:\
              :maxproc-max=512:\
              :maxproc-cur=256:\
              :ignorenologin:\
              :requirehome@:\
              :tc=default:
    '';

    system.activationScripts.login.text = ''
        mkdir -p /run/wrappers/bin
        cp ${pkgs.openbsd.login_passwd}/bin/login_passwd /run/wrappers/bin/login_passwd
        chmod 4555 /run/wrappers/bin/login_passwd
      '';
  };
}
