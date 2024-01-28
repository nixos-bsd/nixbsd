# /etc files related to networking, such as /etc/services.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.networking.resolvconf;

  configText = ''
    # This is the default, but we must set it here to prevent
    # a collision with an apparently unrelated environment
    # variable with the same name exported by dhcpcd.
    interface_order='lo lo[0-9]*'
  '' + optionalString (length cfg.extraOptions > 0) ''
    # Options as described in resolv.conf(5)
    resolv_conf_options='${concatStringsSep " " cfg.extraOptions}'
  '' + optionalString cfg.useLocalResolver ''
    # This hosts runs a full-blown DNS resolver.
    name_servers='127.0.0.1'
  '' + cfg.extraConfig;

in {
  options = {

    networking.resolvconf = {

      enable = mkOption {
        type = types.bool;
        default = !(config.environment.etc ? "resolv.conf");
        defaultText =
          literalExpression ''!(config.environment.etc ? "resolv.conf")'';
        description = lib.mdDoc ''
          Whether DNS configuration is managed by resolvconf.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.openresolv;
        defaultText = literalExpression "pkgs.openresolv";
        description = lib.mdDoc ''
          The package that provides the system-wide resolvconf command.
          Defaults to openresolv if this module is enabled. FreeBSD resolvconf
          also uses opensresolv.
          Otherwise, can be used by other modules to provide a compatibility layer.

          This option generally shouldn't be set by the user.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        example = "libc=NO";
        description = lib.mdDoc ''
          Extra configuration to append to {file}`resolvconf.conf`.
        '';
      };

      extraOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "ndots:1" "rotate" ];
        description = lib.mdDoc ''
          Set the options in {file}`/etc/resolv.conf`.
        '';
      };

      useLocalResolver = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Use local DNS server for resolving.
        '';
      };

    };

  };

  config = mkMerge [
    {
      environment.etc."resolvconf.conf".text = if !cfg.enable then
      # Force-stop any attempts to use resolvconf
      ''
        echo "resolvconf is disabled on this system but was used anyway:" >&2
        echo "$0 $*" >&2
        exit 1
      '' else
        configText;
    }
    (mkIf cfg.enable { environment.systemPackages = [ cfg.package ]; })
  ];

}
