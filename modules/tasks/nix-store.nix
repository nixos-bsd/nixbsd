{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.readOnlyNixStore;
  flag = tag: item: builtins.trace "flag ${builtins.toString tag}: ${builtins.toString item}" item;
in {
  options.readOnlyNixStore = {
    enable = mkEnableOption "Mount the nix store read-only";
    readOnlySource = mkOption {
      type = types.str;
      description = ''
        A filesystem path where the nix store is mounted read only.
      '';
    };
    writableTmpfs = mkOption {
      type = types.bool;
      description = ''
        Set to true to automatically enable a tmpfs layer on top of the read-only layer.
      '';
      default = false;
    };
    writableLayer = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        A read-write filesystem path that can be overlay-mounted on top of the readOnlySource path to make it writable.
        This won't work if readOnlySource is /nix/store.
      '';
    };
  };
  config = mkIf cfg.enable {
    readOnlyNixStore.writableLayer = mkIf cfg.writableTmpfs "/nix/.rw-store";
    fileSystems = mkVMOverride {
      "/nix/.rw-store" = mkIf cfg.writableTmpfs {
        fsType = "tmpfs";
      };
      "/nix/store" = mkIf (cfg.readOnlySource != "/nix/store") {
        fsType = if cfg.writableLayer == null then "nullfs" else "unionfs";
        device = if cfg.writableLayer == null then cfg.readOnlySource else "${cfg.writableLayer}:${cfg.readOnlySource}";
        depends = [ cfg.readOnlySource ] ++ lib.optionals (cfg.writableLayer != null) [ cfg.writableLayer ];
      };
    };
  };
}
