# This module generates nixos-install, nixos-rebuild,
# nixos-generate-config, etc.

{ config, lib, pkgs, ... }:

with lib;

let
  tools = pkgs.callPackages ./package.nix {
    nix = config.nix.package.out;
    nixosVersion = config.system.nixos.version;
    nixosCodeName = config.system.nixos.codeName;
    nixosRevision = config.system.nixos.revision;
    configurationRevision = config.system.configurationRevision;

    inherit config;
  };
in {
  options.system.nixos-generate-config = {
    # flake = lib.mkOption {
    #   internal = true;
    #   type = lib.types.str;
    #   default = defaultFlakeTemplate;
    #   description = ''
    #     The NixOS module that `nixos-generate-config`
    #     saves to `/etc/nixos/flake.nix` if --flake is set.

    #     This is an internal option. No backward compatibility is guaranteed.
    #     Use at your own risk!

    #     Note that this string gets spliced into a Perl script. The perl
    #     variable `$bootLoaderConfig` can be used to
    #     splice in the boot loader configuration.
    #   '';
    # };

    configuration = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "defaultConfigTemplate";
      description = ''
        The NixOS module that `nixos-generate-config`
        saves to `/etc/nixos/configuration.nix`.

        This is an internal option. No backward compatibility is guaranteed.
        Use at your own risk!

        Note that this string gets spliced into a Perl script. The perl
        variable `$bootLoaderConfig` can be used to
        splice in the boot loader configuration.
      '';
    };

    # desktopConfiguration = lib.mkOption {
    #   internal = true;
    #   type = lib.types.listOf lib.types.lines;
    #   default = [ ];
    #   description = ''
    #     Text to preseed the desktop configuration that `nixos-generate-config`
    #     saves to `/etc/nixos/configuration.nix`.

    #     This is an internal option. No backward compatibility is guaranteed.
    #     Use at your own risk!

    #     Note that this string gets spliced into a Perl script. The perl
    #     variable `$bootLoaderConfig` can be used to
    #     splice in the boot loader configuration.
    #   '';
    # };
  };

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
        [ nixos-install nixos-rebuild nixos-version nixos-enter nixos-generate-config ];
    })

    # These may be used in auxiliary scripts (ie not part of toplevel), so they are defined unconditionally.
    ({
      system.build = { inherit (tools) nixos-install nixos-rebuild nixos-enter nixos-generate-config; };
      system.installerDependencies = [ pkgs.installShellFiles ];
    })
  ];

}
