{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.hardware.opengl;

  package = pkgs.buildEnv {
    name = "opengl-drivers";
    paths = [ cfg.package ] ++ cfg.extraPackages;
  };

in

{

  imports = [
    (mkRenamedOptionModule [ "services" "xserver" "vaapiDrivers" ] [ "hardware" "opengl" "extraPackages" ])
    (mkRemovedOptionModule [ "hardware" "opengl" "s3tcSupport" ] "S3TC support is now always enabled in Mesa.")
  ];

  options = {

    hardware.opengl = {
      enable = mkOption {
        description = ''
          Whether to enable OpenGL drivers. This is needed to enable
          OpenGL support in X11 systems, as well as for Wayland compositors
          like sway and Weston. It is enabled by default
          by the corresponding modules, so you do not usually have to
          set it yourself, only if there is no module for your wayland
          compositor of choice. See services.xserver.enable and
          programs.sway.enable.
        '';
        type = types.bool;
        default = false;
      };

      driSupport = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable accelerated OpenGL rendering through the
          Direct Rendering Interface (DRI).
        '';
      };

      driModulePackages = mkOption {
        type = types.listOf types.package;
        default = with pkgs.freebsd; [ drm-kmod drm-kmod-firmware ];
        description = ''
          Kernel modules to install to enable the direct rendering interface
        '';
      };

      package = mkOption {
        type = types.package;
        internal = true;
        description = ''
          The package that provides the OpenGL implementation.
        '';
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        example = literalExpression "with pkgs; [ intel-media-driver intel-ocl intel-vaapi-driver ]";
        description = ''
          Additional packages to add to OpenGL drivers.
          This can be used to add OpenCL drivers, VA-API/VDPAU drivers etc.

          ::: {.note}
          intel-media-driver supports hardware Broadwell (2014) or newer. Older hardware should use the mostly unmaintained intel-vaapi-driver driver.
          :::
        '';
      };

      setLdLibraryPath = mkOption {
        type = types.bool;
        internal = true;
        default = false;
        description = ''
          Whether the `LD_LIBRARY_PATH` environment variable
          should be set to the locations of driver libraries. Drivers which
          rely on overriding libraries should set this to true. Drivers which
          support `libglvnd` and other dispatch libraries
          instead of overriding libraries should not set this.
        '';
      };
    };

  };

  config = mkIf cfg.enable {

    boot.extraModulePackages = mkIf cfg.driSupport cfg.driModulePackages;

    systemd.tmpfiles.rules = [
      "L+ /run/opengl-driver - - - - ${package}"
    ];

    environment.sessionVariables.LD_LIBRARY_PATH = mkIf cfg.setLdLibraryPath [ "/run/opengl-driver/lib" ];

    hardware.opengl.package = mkDefault pkgs.mesa;
  };
}
