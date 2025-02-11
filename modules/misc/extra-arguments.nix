{ lib, config, pkgs, _nixbsdNixpkgsPath, ... }:
with lib;

{
  _module.args = {
    utils = import ../../lib/utils.nix { inherit lib config pkgs; };
  };
}
