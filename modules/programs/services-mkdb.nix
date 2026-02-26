{ config, lib, pkgs, ... }:
with lib;
let cfg = config.programs.services-mkdb;
in {
  options = {
    programs.services-mkdb.package = mkOption {
      type = types.package;
      default = pkgs.freebsd.services_mkdb;
      description = ''
        Package to use for services_mkdb. This is used to make the /etc/services file
        and optionally to generate /var/db/services
      '';
    };
  };

  config = {
    environment.etc.services.source = "${cfg.package}/etc/services";

    # while we're here...
    environment.etc.hosts.source = "${pkgs.freebsd.libc-conf}/etc/hosts";
    environment.etc.netconfig.source = "${pkgs.freebsd.libc-conf}/etc/netconfig";
    environment.etc."nsswitch.conf".source = "${pkgs.freebsd.libc-conf}/etc/nsswitch.conf";
    environment.etc.protocols.source = "${pkgs.freebsd.libc-conf}/etc/protocols";
  };
}
