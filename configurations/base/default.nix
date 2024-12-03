{ config, lib, pkgs, ... }: {
  nixpkgs.hostPlatform = "x86_64-openbsd";
  nixpkgs.config.freebsdBranch = "release/14.1.0";
  boot.kernel.package = pkgs.openbsd.sys;

  #users.users.root.initialPassword = "toor";

  # Don't make me wait for an address...
  #networking.dhcpcd.wait = "background";

  #users.users.bestie = {
  #  isNormalUser = true;
  #  description = "your bestie";
  #  extraGroups = [ "wheel" ];
  #  inherit (config.users.users.root) initialPassword;
  #};

  #services.sshd.enable = true;
  boot.loader.stand-openbsd.enable = true;

  fileSystems."/" = {
    device = "/dev/ufs/nixos";
    fsType = "ufs";
  };

  fileSystems."/boot" = {
    device = "/dev/msdosfs/ESP";
    fsType = "msdosfs";
  };
}
