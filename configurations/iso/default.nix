# NixBSD ISO image configuration
# Produces a bootable live ISO suitable for installation or recovery.
#
# Build with: nix build .#iso.isoImage
{ config, lib, pkgs, ... }:
{
  imports = [
    ../../modules/installer/cd-dvd/iso-image.nix
    ../../modules/installer/cd-dvd/iso-live-boot.nix
  ];

  nixpkgs.hostPlatform = "x86_64-freebsd";

  # ISO image settings
  isoImage.isoName = "nixbsd-${config.system.nixos.label}.iso";
  isoImage.volumeID = "NIXBSD_ISO";

  # Boot loader
  boot.loader.stand-freebsd.enable = true;

  # Root password for the live environment
  users.users.root.initialPassword = "nixbsd";

  # A regular user for the live environment
  users.users.nixbsd = {
    isNormalUser = true;
    description = "NixBSD Live User";
    extraGroups = [ "wheel" ];
    initialPassword = "nixbsd";
  };

  # Enable SSH for remote access
  services.sshd.enable = true;

  # Use C.UTF-8 locale which is built into FreeBSD's C library and doesn't
  # require external locale files to be accessible at login time.
  i18n.defaultLocale = "C.UTF-8";

  # Networking
  networking.dhcpcd.wait = "background";

  # Basic packages for an installation/recovery environment
  environment.systemPackages = with pkgs; [
    file
    gitMinimal
    htop
    tmux
    vim
  ];

  # Include installer tools
  system.includeInstallerDependencies = true;

  # Enable flakes and nix-command for convenience
  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
