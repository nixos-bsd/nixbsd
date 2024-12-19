{ pkgs, lib, ... }:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;

  programs.less.enable = lib.mkForce false;
  security.sudo.enable = lib.mkForce false;
  xdg.mime.enable = false;
}
