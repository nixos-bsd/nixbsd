# This module generates nixos-install, nixos-rebuild,
# nixos-generate-config, etc.

{ config, lib, pkgs, ... }:

with lib;

let
  tools = pkgs.callPackages ./package.nix {
    nix = config.nix.package.out;
    nixosVersion = config.system.nixos.version;
    nixosRevision = config.system.nixos.revision;
    configurationRevision = config.system.configurationRevision;
  };
in {

  options.system.disableInstallerTools = mkOption {
    internal = true;
    type = types.bool;
    default = false;
    description = ''
      Disable nixos-rebuild, nixos-generate-config, nixos-installer
      and other NixOS tools. This is useful to shrink embedded,
      read-only systems which are not expected to be rebuild or
      reconfigure themselves. Use at your own risk!
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (config.nix.enable && !config.system.disableInstallerTools) {
      environment.systemPackages = with tools;
        [ nixos-install nixos-rebuild nixos-version nixos-enter ];
    })

    # These may be used in auxiliary scripts (ie not part of toplevel), so they are defined unconditionally.
    ({
      system.build = { inherit (tools) nixos-install nixos-rebuild nixos-enter; };
      system.installerDependencies = [ pkgs.installShellFiles ];
    })
  ];

}
