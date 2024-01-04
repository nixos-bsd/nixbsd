{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.boot.kernel.sysctl;
  sysctlOption = mkOptionType {
    name = "sysctl option value";
    check = val:
      let checkType = x: isBool x || isString x || isInt x || x == null;
      in checkType val
      || (val._type or "" == "override" && checkType val.content);
    merge = loc: defs: mergeOneOption loc (filterOverrides defs);
  };

in {

  options = {

    boot.kernel.sysctl = mkOption {
      type = types.submodule { freeformType = types.attrsOf sysctlOption; };
      default = { };
      example = literalExpression ''
        { "kern.sync_on_panic" = false; "kern.maxvnodes" = 4096; }
      '';
      description = lib.mdDoc ''
        Runtime parameters of the FreeBSD kernel, as set by
        {manpage}`sysctl(8)`.  Note that sysctl
        parameters names must be enclosed in quotes
        (e.g. `"kern.sync_on_panic"` instead of
        `kern.sync_on_panic`).  The value of each
        parameter may be a string, integer, boolean, or null
        (signifying the option will not appear at all).
      '';

    };

  };

  config = mkIf (cfg != { }) {

    environment.etc."sysctl.conf".text = concatStrings (mapAttrsToList (n: v:
      optionalString (v != null) ''
        ${n}=${if v == false then "0" else toString v}
      '') cfg);

    rc.services.sysctl = {
      description = "Set sysctl variables";
      provides = "sysctl";
      commands.start =
        "${pkgs.freebsd.sysctl}/bin/sysctl -i -f /etc/sysctl.conf";
    };

    rc.services.sysctl-lastload = {
      description = "Set sysctl variables after services are started";
      provides = "sysctl_lastload";
      requires = [ "LOGIN" ];
      before = [ "jail" ];
      commands.start = "${pkgs.freebsd.sysctl}/bin/sysctl -f /etc/sysctl.conf";
    };

  };
}
