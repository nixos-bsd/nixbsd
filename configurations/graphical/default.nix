{ ... }: {
  imports = [ ../base/default.nix ];

  services.xserver = {
    enable = true;
    displayManager.sddm.enable = true;
    desktopManager.xfce = {
      enable = true;
    };
    #libinput.enable = true; # for touchpad support on many laptops
  };
}
