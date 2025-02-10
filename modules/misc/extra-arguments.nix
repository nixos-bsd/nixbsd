{ lib, config, pkgs, _nixbsdNixpkgsPath, ... }:
with lib;

{
  _module.args = {
    utils = import ../../lib/utils.nix { inherit lib config pkgs; };
  };

  options.__realBuildPlatform = mkOption {
    type = types.str;
    default = config.nixpkgs.buildPlatform;
  };
  options.buildTrivial = mkOption {
    default = if config.__realBuildPlatform == config.nixpkgs.buildPlatform then pkgs
    else if config.__realBuildPlatform != config.nixpkgs.hostPlatform then throw "Misuse of __realBuildPlatform"
    else let
      stdenv' = pkgs.stdenv // { buildPlatform = pkgs.stdenv.hostPlatform; };
      stdenvNoCC' = pkgs.stdenvNoCC // { buildPlatform = pkgs.stdenvNoCC.hostPlatform; };
      mkMkDerivation = import "${_nixbsdNixpkgsPath}/pkgs/stdenv/generic/make-derivation.nix" { inherit lib; config = config.nixpkgs; };
      mkStdenv = stdenv: stdenv // (mkMkDerivation stdenv);
      spliceLies = drv: drv // optionalAttrs (drv?__spliced) { __spliced = drv.__spliced // (with drv.__spliced; {
        buildBuild = hostHost;
        buildHost = hostHost;
        buildTarget = hostTarget;
      }); };
      toLieIn = [ "buildInputs" "nativeBuildInputs" "depsBuildBuild" "depsBuildHost" "depsBuildTarget" "depsHostHost" "depsHostTarget" "depsTargetTarget" ];
      installLiesOne = func: if builtins.isFunction func then installLiesOne (args: func (if builtins.isAttrs args then (lib.mapAttrs (name: val: if builtins.elemOf name toLieIn then lib.map spliceLies val else val) args) else args)) else func;
      trivialSet = import "${_nixbsdNixpkgsPath}/pkgs/build-support/trivial-builders" {
        inherit lib;
        config = config.nixpkgs;
        stdenv = mkStdenv stdenv';
        stdenvNoCC = mkStdenv stdenvNoCC';
        inherit (pkgs) jq lndir runtimeShell shellcheck-minimal;
      };
      lyingTrivialSet = lib.mapAttrs (_: installLiesOne) trivialSet;
    in lyingTrivialSet;
  };
}
