{ lib, pkgs, ... }: with lib; {
    security = {
      polkit.enable = true;
      pam.services.swaylock = {};
    };

    hardware.opengl.enable = mkDefault true;
    fonts.enableDefaultPackages = mkDefault true;

    services.seatd.enable = true;

    programs = {
      dconf.enable = mkDefault true;
      xwayland.enable = mkDefault true;
    };
}
