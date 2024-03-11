{ pkgs, _nixbsdNixpkgsPath, ... }:
let
  pkgsLinux = import _nixbsdNixpkgsPath {
    inherit (pkgs) overlays;
    localSystem = "x86_64-linux";
  };
in {
  imports = [ ../extra/default.nix ];

  boot.linux.enable = true;

  environment.systemPackages = [ pkgsLinux.hello ];
}
