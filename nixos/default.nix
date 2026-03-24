let
# Based on <nixpkgs/nixos> entrypoint for flake-less systems
# Still using some hard-coded flake references for compatibility issues
  fromENV =
    name: default:
    let
      value = builtins.getEnv name;
    in
    if value == "" then default else value;

  fromDiamond = path: default: if (builtins.tryEval path).success then path else default;

  flakeInfo = builtins.fromJSON (builtins.readFile ../flake.lock);
  fromFlake =
    name:
    let
      nodeName = flakeInfo.nodes.root.inputs.${name};
      node = flakeInfo.nodes.${nodeName};
      inherit (node.locked)
        lastModified
        narHash
        owner
        repo
        rev
        type
        ;
    in
    builtins.fetchTarball {
      url =
        flakeInfo.nodes.${nodeName}.locked.url
          or "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";

      sha256 = narHash;
    };

  diamondConfig = fromDiamond <nixbsd-config> <nixos-config>;
in
{
  configuration ? fromENV "NIXBSD_CONFIG" (fromENV "NIXOS_CONFIG" diamondConfig),
  pkgs ? import <nixpkgs> { },
  system ? builtins.currentSystem,
  # This should only be used for special arguments that need to be evaluated when resolving module structure (like in imports).
  # For everything else, there's _module.args.
  specialArgs ? { },
}:

let

  eval = import ../lib/eval-config.nix {
    inherit system;
    inherit (pkgs) lib;
    nixpkgsPath = pkgs.path;

    modules = [ configuration ];

    specialArgs = {
      #lixFlake = lix;
      lixFlake = null;
      cppnixFlake = import (fromFlake "cppnix"); # can be overriden w/ specialArgs
      mini-tmpfiles-overlay = import "${fromFlake "mini-tmpfiles"}/overlay.nix"; # can be overriden w/ specialArgs
    }
    // specialArgs;
  };
in

{
  inherit (eval) pkgs config options;

  system = eval.config.system.build.toplevel;

  # inherit (eval.config.system.build) vm vmWithBootLoader;
}
