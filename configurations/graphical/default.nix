{ ... }: {
  imports = [ ../base/default.nix ];
  environment.etc.machine-id.text = "53ce9ee8540445a49241d28f5ca77d52";

  services.dbus.enable = true;
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.xfce = {
      enable = true;
    };
    exportConfiguration = true;
    #libinput.enable = true; # for touchpad support on many laptops
  };
}
