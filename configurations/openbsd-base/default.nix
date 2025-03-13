{ pkgs, lib, config, ... }:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  nixpkgs.overlays = [
    (import ../../overlays/nix-patches.nix)
  ];
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;

  # users.users.root.initialPassword = "toor";
  users.users.root.initialHashedPassword = "$2b$09$CexHNp84.dJLZv5oBcSBuO7zLdbAIBxyxiukAPwY3yKiH162s.GGW";

  users.users.bestie = {
    isNormalUser = true;
    description = "your bestie";
    extraGroups = [ "wheel" ];
    inherit (config.users.users.root) initialHashedPassword;
  };

  environment.systemPackages = [
    pkgs.openbsd.kdump
    pkgs.openbsd.ktrace
    pkgs.neofetch
  ];

  virtualisation.vmVariant.virtualisation.diskImage = "./${config.system.name}.qcow2";

  services.sshd.enable = true;

  xdg.mime.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  programs.bash.completion.enable = false;
}
