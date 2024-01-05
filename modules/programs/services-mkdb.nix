{ config, lib, pkgs, ... }:
with lib;
let cfg = config.programs.services-mkdb;
in {
  options = {
    programs.services-mkdb.package = mkOption {
      type = types.package;
      default = pkgs.freebsd.services_mkdb;
      description = lib.mdDoc ''
        Package to use for services_mkdb. This is used to make the /etc/services file
        and optionally to generate /var/db/services
      '';
    };
  };

  config = { environment.etc.services.source = "${cfg.package}/etc/services"; };
}
