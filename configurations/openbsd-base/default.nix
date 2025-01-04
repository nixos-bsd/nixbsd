{ pkgs, lib, config, ... }:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
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

  environment.systemPackages = [ pkgs.neofetch pkgs.nano ];

  virtualisation.vmVariant.virtualisation.diskImage = "./${config.system.name}.qcow2";

  services.sshd.enable = true;

  programs.less.enable = lib.mkForce false;
  xdg.mime.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  nix.enable = false;
  programs.bash.completion.enable = false;
  system.switch.enable = false;
}
