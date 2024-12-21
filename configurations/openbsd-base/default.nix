{ pkgs, lib, config, ... }:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;

  virtualisation.vmVariant.virtualisation.diskImage = "./${config.system.name}.qcow2";

  programs.less.enable = lib.mkForce false;
  security.sudo.enable = lib.mkForce false;
  xdg.mime.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  nix.enable = false;
  programs.bash.completion.enable = false;
  system.switch.enable = false;
}
