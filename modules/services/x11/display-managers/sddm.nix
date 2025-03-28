{ config, lib, pkgs, ... }:

with lib;
let
  xcfg = config.services.xserver;
  dmcfg = xcfg.displayManager;
  cfg = dmcfg.sddm;
  xEnv = config.init.services.display-manager.environment;

  sddm = cfg.package;

  iniFmt = pkgs.formats.ini { };

  xserverWrapper = pkgs.writeShellScript "xserver-wrapper" ''
    ${concatMapStrings (n: "export ${n}=\"${getAttr n xEnv}\"\n") (attrNames xEnv)}
    exec systemd-cat -t xserver-wrapper ${dmcfg.xserverBin} ${toString dmcfg.xserverArgs} "$@"
  '';

  Xsetup = pkgs.writeShellScript "Xsetup" ''
    ${cfg.setupScript}
    ${dmcfg.setupCommands}
  '';

  Xstop = pkgs.writeShellScript "Xstop" ''
    ${cfg.stopScript}
  '';

  defaultConfig = {
    General = {
      HaltCommand = "poweroff";
      RebootCommand = "reboot";
      Numlock = if cfg.autoNumlock then "on" else "none"; # on, off none

      # Implementation is done via pkgs/applications/display-managers/sddm/sddm-default-session.patch
      DefaultSession = optionalString (dmcfg.defaultSession != null) "${dmcfg.defaultSession}.desktop";

      DisplayServer = if cfg.wayland.enable then "wayland" else "x11";
    };

    Theme = {
      Current = cfg.theme;
      ThemeDir = "/run/current-system/sw/share/sddm/themes";
      FacesDir = "/run/current-system/sw/share/sddm/faces";
    };

    Users = {
      MaximumUid = config.ids.uids.nixbld;
      HideUsers = concatStringsSep "," dmcfg.hiddenUsers;
      HideShells = "/run/current-system/sw/bin/nologin";
    };

    X11 = {
      MinimumVT = if xcfg.tty != null then xcfg.tty else 7;
      ServerPath = toString xserverWrapper;
      XephyrPath = "${pkgs.xorg.xorgserver.out}/bin/Xephyr";
      SessionCommand = toString dmcfg.sessionData.wrapper;
      SessionDir = "${dmcfg.sessionData.desktops}/share/xsessions";
      XauthPath = "${pkgs.xorg.xauth}/bin/xauth";
      DisplayCommand = toString Xsetup;
      DisplayStopCommand = toString Xstop;
      EnableHiDPI = cfg.enableHidpi;
    };

    Wayland = {
      EnableHiDPI = cfg.enableHidpi;
      SessionDir = "${dmcfg.sessionData.desktops}/share/wayland-sessions";
      CompositorCommand = lib.optionalString cfg.wayland.enable cfg.wayland.compositorCommand;
    };
  } // lib.optionalAttrs dmcfg.autoLogin.enable {
    Autologin = {
      User = dmcfg.autoLogin.user;
      Session = autoLoginSessionName;
      Relogin = cfg.autoLogin.relogin;
    };
  };

  cfgFile =
    iniFmt.generate "sddm.conf" (lib.recursiveUpdate defaultConfig cfg.settings);

  autoLoginSessionName =
    "${dmcfg.sessionData.autologinSession}.desktop";

in
{
  options = {

    services.xserver.displayManager.sddm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable sddm as the display manager.
        '';
      };

      package = mkPackageOption pkgs [ "qt6Packages" "sddm" ] {};

      enableHidpi = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable automatic HiDPI mode.
        '';
      };

      settings = mkOption {
        type = iniFmt.type;
        default = { };
        example = {
          Autologin = {
            User = "john";
            Session = "plasma.desktop";
          };
        };
        description = ''
          Extra settings merged in and overwriting defaults in sddm.conf.
        '';
      };

      theme = mkOption {
        type = types.str;
        default = "";
        description = ''
          Greeter theme to use.
        '';
      };

      autoNumlock = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable numlock at login.
        '';
      };

      setupScript = mkOption {
        type = types.str;
        default = "";
        example = ''
          # workaround for using NVIDIA Optimus without Bumblebee
          xrandr --setprovideroutputsource modesetting NVIDIA-0
          xrandr --auto
        '';
        description = ''
          A script to execute when starting the display server. DEPRECATED, please
          use {option}`services.xserver.displayManager.setupCommands`.
        '';
      };

      stopScript = mkOption {
        type = types.str;
        default = "";
        description = ''
          A script to execute when stopping the display server.
        '';
      };

      # Configuration for automatic login specific to SDDM
      autoLogin = {
        relogin = mkOption {
          type = types.bool;
          default = false;
          description = ''
            If true automatic login will kick in again on session exit (logout), otherwise it
            will only log in automatically when the display-manager is started.
          '';
        };

        minimumUid = mkOption {
          type = types.ints.u16;
          default = 1000;
          description = ''
            Minimum user ID for auto-login user.
          '';
        };
      };

      # Experimental Wayland support
      wayland = {
        enable = mkEnableOption "experimental Wayland support";

        compositorCommand = mkOption {
          type = types.str;
          internal = true;

          # This is basically the upstream default, but with Weston referenced by full path
          # and the configuration generated from NixOS options.
          default = let westonIni = (pkgs.formats.ini {}).generate "weston.ini" {
              libinput = {
                enable-tap = xcfg.libinput.mouse.tapping;
                left-handed = xcfg.libinput.mouse.leftHanded;
              };
              keyboard = {
                keymap_model = xcfg.xkb.model;
                keymap_layout = xcfg.xkb.layout;
                keymap_variant = xcfg.xkb.variant;
                keymap_options = xcfg.xkb.options;
              };
            }; in "${pkgs.weston}/bin/weston --shell=fullscreen-shell.so -c ${westonIni}";
          description = "Command used to start the selected compositor";
        };
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = xcfg.enable;
        message = ''
          SDDM requires services.xserver.enable to be true
        '';
      }
      {
        assertion = dmcfg.autoLogin.enable -> autoLoginSessionName != null;
        message = ''
          SDDM auto-login requires that services.xserver.displayManager.defaultSession is set.
        '';
      }
    ];

    services.xserver.displayManager.job = {
      environment = {
        # Load themes from system environment
        QT_PLUGIN_PATH = "/run/current-system/sw/" + pkgs.qt6.qtbase.qtPluginPrefix;
        QML2_IMPORT_PATH = "/run/current-system/sw/" + pkgs.qt6.qtbase.qtQmlPrefix;
      };

      execCmd = [ "${pkgs.qt6Packages.sddm}/bin/sddm" ];
    };

    security.pam.services = {
      sddm.text = ''
        auth      substack      login
        account   include       login
        password  substack      login
        session   include       login
      '';

      sddm-greeter.text = ''
        auth     required       pam_succeed_if.so audit quiet_success user = sddm
        auth     optional       pam_permit.so

        account  required       pam_succeed_if.so audit quiet_success user = sddm
        account  sufficient     pam_unix.so

        password required       pam_deny.so

        session  required       pam_succeed_if.so audit quiet_success user = sddm
        session  required       pam_env.so conffile=/etc/pam/environment readenv=0
        session  optional       pam_keyinit.so force revoke
        session  optional       pam_permit.so
      '';

      sddm-autologin.text = ''
        auth     requisite pam_nologin.so
        auth     required  pam_succeed_if.so uid >= ${toString cfg.autoLogin.minimumUid} quiet
        auth     required  pam_permit.so

        account  include   sddm

        password include   sddm

        session  include   sddm
      '';
    };

    users.users.sddm = {
      createHome = true;
      home = "/var/lib/sddm";
      group = "sddm";
      uid = config.ids.uids.sddm;
    };

    environment.etc."sddm.conf".source = cfgFile;
    environment.pathsToLink = [
      "/share/sddm"
    ];

    users.groups.sddm.gid = config.ids.gids.sddm;

    environment.systemPackages = [ sddm ];
    services.dbus.packages = [ sddm ];
    #systemd.tmpfiles.packages = [ sddm ];

    # We're not using the upstream unit, so copy these: https://github.com/sddm/sddm/blob/develop/services/sddm.service.in
    #systemd.services.display-manager.after = [
    #  "systemd-user-sessions.service"
    #  "getty@tty7.service"
    #  "plymouth-quit.service"
    #  "systemd-logind.service"
    #];
    #systemd.services.display-manager.conflicts = [
    #  "getty@tty7.service"
    #];

    # To enable user switching, allow sddm to allocate TTYs/displays dynamically.
    services.xserver.tty = null;
    services.xserver.display = null;
  };
}
