{ lib, ... }:
{
  options.systemd.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [];
    description = "This option exists only for compatibility with NixOS modules and does not have any effect.";
  };
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = [];
    description = "This option exists only for compatibility with NixOS modules and does not have any effect.";
  };
  options.security.sudo-rs = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = [];
    description = "This option exists only for compatibility with NixOS modules and does not have any effect.";
  };
}
