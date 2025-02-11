{ lib, config, pkgs, _nixbsdNixpkgsPath, ... }:
with lib;
{
  options._realBuildPlatform = mkOption {
    type = types.str;
    default = "";
    description = "A hack.";
    internal = true;
  };

  options.buildTrivial = mkOption {
    description = "Another hack.";
    internal = true;
    defaultText = "pkgs";
    default = if config._realBuildPlatform == "" || config._realBuildPlatform == pkgs.stdenv.buildPlatform.system then pkgs
    else if config._realBuildPlatform != pkgs.stdenv.hostPlatform.system then throw "Misuse of _realBuildPlatform `${config._realBuildPlatform}`"
    else let
      stdenvAddons = {
        buildPlatform = pkgs.stdenv.hostPlatform;
        shell = lib.getExe pkgs.bash;
        extraNativeBuildInputs = lib.map spliceLies pkgs.stdenv.extraNativeBuildInputs;
        extraBuildInputs = lib.map spliceLies pkgs.stdenv.extraBuildInputs;
      };
      stdenv' = pkgs.stdenv // stdenvAddons // { cc = pkgs.clang; };
      stdenvNoCC' = pkgs.stdenvNoCC // stdenvAddons;
      mkMkDerivation = import "${_nixbsdNixpkgsPath}/pkgs/stdenv/generic/make-derivation.nix" { inherit lib; config = pkgs.config; };
      mkStdenv = stdenv: stdenv // (mkMkDerivation stdenv);
      spliceLies = drv: drv // optionalAttrs (drv?__spliced) { __spliced = drv.__spliced // (with drv.__spliced; {
        buildBuild = hostHost;
        buildHost = hostHost;
        buildTarget = hostTarget;
      }); };
      toLieIn = [ "buildInputs" "nativeBuildInputs" "depsBuildBuild" "depsBuildHost" "depsBuildTarget" "depsHostHost" "depsHostTarget" "depsTargetTarget" ];
      installLiesOne = func: if builtins.isFunction func then (args: let result = func (if builtins.isAttrs args then (lib.mapAttrs (name: val: if builtins.elem name toLieIn then lib.map spliceLies val else val) args) else args); in if builtins.isFunction result then installLiesOne result else result) else func;
      trivialSet = import "${_nixbsdNixpkgsPath}/pkgs/build-support/trivial-builders" {
        inherit lib;
        config = pkgs.config;
        stdenv = mkStdenv stdenv';
        stdenvNoCC = mkStdenv stdenvNoCC';
        jq = spliceLies pkgs.jq;
        lndir = spliceLies pkgs.lndir;
        runtimeShell = lib.getExe pkgs.bash;
        shellcheck-minimal = spliceLies pkgs.shellcheck-minimal;
      };
      lyingTrivialSet = lib.mapAttrs (_: installLiesOne) trivialSet;
    in lyingTrivialSet;
  };
}
