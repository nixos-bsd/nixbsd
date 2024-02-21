{ config, lib, nixFlake ? null, ... }:
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
  };

  config = {
    nixpkgs.overlays = mkIf (nixFlake != null && config.nixpkgs.overrideNix) [
      nixFlake.overlays.default
      (final: prev: { nix = prev.nix.override { enableManual = false; }; })
    ];
  };
}
