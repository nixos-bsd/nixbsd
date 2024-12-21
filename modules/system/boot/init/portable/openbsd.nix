{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
let
  convertService = name: cfg: throw "ummmmm";
in
{
  config = mkMerge [
    { init.backend = mkOptionDefault "openbsd"; }
    (mkIf (config.init.backend == "openbsd") {
      openbsd.rc.services = lib.mapAttrs convertService config.init.services;
    })
  ];
}
