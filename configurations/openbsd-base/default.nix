{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;
}
