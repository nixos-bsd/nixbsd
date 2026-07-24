{
  config,
  lib,
  mini-tmpfiles-flake ? null,
  ...
}:
with lib;
{
  options = {
    # TODO: remove when stable nix >= 2.35
    nixpkgs.overrideNix = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Overlay nix with the latest version of nix.

        This only works when building with a flake and `nixpkgs.pkgs` is not set manually.

        When this option is enabled then the overlay is enabled so that
        packages and options that require a working nix can build.
      '';
    };
    # TODO: @sky1e remove once mini-tmpfiles is a proper package
    # Also remove specialArgs and input changes in flake
    nixpkgs.overrideMiniTmpfiles = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Overlay mini-tmpfiles. (github:nixos-bsd/mini-tmpfiles)
        This is currently nonfunctional, but is intended to become a dependency of
        nixbsd to handle the responsibilities systemd-tmpfiles handles on nixos. For now
        it is included to validate that it builds and runs on nixbsd.
        Overlay nix with the development version.

        This only works when building with a flake and `nixpkgs.pkgs` is not set manually.

        This option is temporary to aid in the development of nixbsd.
      '';
    };
  };

  config = {
    nixpkgs.overlays =
      lib.optionals config.nixpkgs.overrideNix [
        (_: prev: { nix = prev.nixVersions.latest; })
      ]
      ++ lib.optional (
        mini-tmpfiles-flake != null && config.nixpkgs.overrideMiniTmpfiles
      ) mini-tmpfiles-flake.overlays.default
      ++ [ (import ../../overlays/pkgs.nix) ];
  };
}
