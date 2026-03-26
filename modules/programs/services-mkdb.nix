{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.services-mkdb;

  protocols =
    let
      path = "lib/libc/net/protocols";
      pname = "protocols";
    in
    pkgs.runCommand "etc-${pname}"
      {
        src = pkgs.freebsd.filterSource {
          inherit pname path;
        };
        meta.platforms = lib.platforms.freebsd;
      }
      ''
        mkdir -p $out/etc
        ln -sf $src/${path} $out/etc/${pname}
      '';
in
{
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
    environment.etc.protocols.source = "${protocols}/etc/protocols";
  };
}
