final: prev: let
  pkgNames = builtins.attrNames (builtins.readDir ../pkgs);
  mkPkg = name: { inherit name; value = final.callPackage ../pkgs/${name}/package.nix {}; };
  pkgs = builtins.listToAttrs (builtins.map mkPkg pkgNames);
in pkgs
