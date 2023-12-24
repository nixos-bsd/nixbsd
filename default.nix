{
  configuration ? import <nixpkgs/nixos/lib/from-env.nix> "NIXBSD_CONFIG" <nixbsd-config.nix>
, system ? builtins.currentSystem
}: let
  nixpkgs = import <nixpkgs> {};
  lib = nixpkgs.lib;
  system = import ./modules/system.nix;
  eval = lib.evalModules {
    modules = [ system configuration ];
    specialArgs = { inherit nixpkgs; };
  };
in {
  inherit (eval) pkgs config options;
  system = eval.config.toplevel;
}
