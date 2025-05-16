{ pkgs, lib, ... }: {
  imports = [ ../base/default.nix ];
  environment.etc.machine-id.text = "53ce9ee8540445a49241d28f5ca77d52\n";
  virtualisation.vmVariant.virtualisation.rootSize = "11g";

  nixpkgs.config.allowUnfree = true;

  security.sudo.wheelNeedsPassword = false;
  hardware.opengl.enable = true;
  services.dbus.enable = true;
  services.seatd.enable = true;
  services.desktopManager.plasma6.enable = true;
  hardware.opengl.driModulePackages = with pkgs.freebsd; [
    drm-kmod
    nvidia-driver
    nvidia-drm-kmod
    nvidia-drm-kmod-firmware
  ];
  environment.systemPackages = with pkgs; [
    freebsd.truss
    gdb
    vim
    clang
  ];
  boot.kernelEnvironment = {
    "hint.uart.0.flags" = "0x80";
    "hint.uart.0.port" = "0x2f8";
    "hw.nvidiadrm.modeset"= "1";
  };
  boot.kernelModules = [ "nvidia-drm" "nvidia_gsp_ga10x_fw" "nvidia_gsp_tu10x_fw" ];
  boot.kernel.package = pkgs.freebsd.sys.override {
    extraConfig = ''
      options DDB
      options KDB
      options GDB
      makeoptions DEBUG="-g -O1"
    '';
  };
  services.xserver.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.consolekit2.enable = true;
}
