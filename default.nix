{ configuration ?
  import <nixpkgs/nixos/lib/from-env.nix> "NIXBSD_CONFIG" <nixbsd-config.nix>
, system ? builtins.currentSystem }:
let
  eval = import ./lib/eval-config.nix {
    inherit system;
    modules = [ configuration ];
  };
in {
  inherit (eval) pkgs config options;

  system = eval.config.system.build.toplevel;
}
