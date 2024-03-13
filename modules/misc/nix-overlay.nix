{ config, lib, nixFlake ? null, mini-tmpfiles-flake ? null, ... }:
with lib; {
  # TODO: @artemist remove when support is upstream
  # Also remove specialArgs and input changes in flake
  options = {
    nixpkgs.overrideNix = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = lib.mdDoc ''
        Overlay nix with the development version.

        This only works when building with a flake and `nixpkgs.pkgs` is not set manually.

        The nixbsd flake includes an input for the development version of nix
        for FreeBSD. When this option is enabled then the overlay is enabled so that
        packages and options that require a working nix can build.

        This option is temporary and will be removed once FreeBSD support is upstream.
      '';
    };
    # TODO: @sky1e remove once mini-tmpfiles is a proper package
    nixpkgs.overrideMiniTmpfiles = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = lib.mdDoc ''
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
      lib.optional (nixFlake != null && config.nixpkgs.overrideNix)
      nixFlake.overlays.default ++ lib.optional
      (mini-tmpfiles-flake != null && config.nixpkgs.overrideMiniTmpfiles)
      mini-tmpfiles-flake.overlays.default;
  };
}
