{ config, lib, ... }:

with lib;

let
  cfg = config.services.xserver.windowManager;
in

{
  imports = [
    ./none.nix ];

  options = {

    services.xserver.windowManager = {

      session = mkOption {
        internal = true;
        default = [];
        example = [{
          name = "wmii";
          start = "...";
        }];
        description = lib.mdDoc ''
          Internal option used to add some common line to window manager
          scripts before forwarding the value to the
          `displayManager`.
        '';
        apply = map (d: d // {
          manage = "window";
        });
      };
    };

  };

  config = {
    services.xserver.displayManager.session = cfg.session;
  };
}
