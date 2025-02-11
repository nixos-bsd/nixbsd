{ lib, config, _nixbsdNixpkgsPath, ... }:
with lib;
let
  localSystem = config.nixpkgs.buildPlatform;
  crossSystem = config.nixpkgs.hostPlatform;
  basePkgs = import _nixbsdNixpkgsPath {
    inherit (config.nixpkgs) config overlays;
    inherit localSystem crossSystem;
  };
  stdenvArgs = {
    name = "stdenvNoCC-lies";
    shell = lib.getExe pkgs.bash;
    config = pkgs.config;
    fetchurlBoot = pkgs.fetchurl;
    # hm.
    initialPath = builtins.map (drv: pkgs.${drv.pname}) pkgs.stdenv.initialPath;
    extraNativeBuildInputs = builtins.map spliceLies pkgs.stdenv.extraNativeBuildInputs;
    extraBuildInputs = builtins.map spliceLies pkgs.stdenv.extraBuildInputs;
    buildPlatform = pkgs.stdenv.hostPlatform;
    hostPlatform = pkgs.stdenv.hostPlatform;
    targetPlatform = pkgs.stdenv.targetPlatform;
  };
  stdenvNoCC' = import "${_nixbsdNixpkgsPath}/pkgs/stdenv/generic" (stdenvArgs // { cc = null; });
  stdenv' = import "${_nixbsdNixpkgsPath}/pkgs/stdenv/generic" (stdenvArgs // { cc = pkgs.clang; });
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
in

{
  options._realBuildPlatform = mkOption {
    type = types.str;
    default = "";
    description = "A hack.";
    internal = true;
  };

  config = mkIf (config._realBuildPlatform != "") {
    nixpkgs.pkgs = basePkgs // lyingTrivialSet;
  };
}
