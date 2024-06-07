{ lib, config, ... }:
with lib;
let cfg = config.nixbsd;
in {
  options = {
    nixbsd.enableExtraSubstituters = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Enable extra substituters from the NixBSD developers
      '';
    };
  };

  config = {
    nix.settings = mkIf cfg.enableExtraSubstituters {
      substituters = [ "https://attic.mildlyfunctional.gay/nixbsd" ];
      trusted-public-keys =
        [ "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc=" ];
    };
  };
}
