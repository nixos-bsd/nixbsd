{ pkgs, lib, ... }: {
  imports = [ ../base/default.nix ];
  environment.etc.machine-id.text = "53ce9ee8540445a49241d28f5ca77d52\n";

  hardware.opengl.enable = true;
  # Intel kmod firmware is unfree, allow all unfree firmware
  nixpkgs.config.allowUnfreePredicate = pkg:
    ((pkg.meta or {}).sourceProvenance or []) == [ lib.sourceTypes.binaryFirmware ];

  #programs.sway.enable = true;

  services.dbus.enable = true;
  services.xserver.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.consolekit2.enable = true;
  security.sudo.wheelNeedsPassword = false;
  services.seatd.enable = true;
  services.desktopManager.plasma6.enable = true;
}
