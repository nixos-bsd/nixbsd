{ config, lib, ... }: {
  nixpkgs.hostPlatform = "x86_64-freebsd";

  users.users.root.initialPassword = "toor";

  # Don't make me wait for an address...
  networking.dhcpcd.wait = "background";

  users.users.bestie = {
    isNormalUser = true;
    description = "your bestie";
    extraGroups = [ "wheel" ];
    inherit (config.users.users.root) initialPassword;
  };
  nix.settings.trusted-users = [ "bestie" ];

  services.sshd.enable = true;
  boot.loader.stand-freebsd.enable = true;

  fileSystems."/" = {
    device = "/dev/gpt/${config.networking.hostName}";
    fsType = "ufs";
  };

  fileSystems."/boot" = {
    device = "/dev/gpt/${config.networking.hostName}-ESP";
    fsType = "msdosfs";
  };

  virtualisation.vmVariant.virtualisation.diskImage = "./${config.system.name}.qcow2";
}
