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
      description = ''
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

  config = let sysctlBin = if pkgs.stdenv.hostPlatform.isOpenBSD then lib.getExe pkgs.openbsd.sysctl else if pkgs.stdenv.hostPlatform.isFreeBSD then lib.getExe pkgs.freebsd.sysctl else (throw "???"); in mkIf (cfg != { }) {

    environment.etc."sysctl.conf".text = concatStrings (mapAttrsToList (n: v:
      optionalString (v != null) ''
        ${n}=${if v == false then "0" else toString v}
      '') cfg);

    init.services.sysctl = {
      description = "Set sysctl variables";
      startType = "oneshot";
      startCommand = [ "${sysctlBin}" "-i" "-f" "/etc/sysctl.conf" ];
    };

    init.services.sysctl-lastload = {
      description = "Set sysctl variables after services are started";
      dependencies = [ "LOGIN" ];
      before = [ "jail" ];

      startType = "oneshot";
      startCommand = [ "${sysctlBin}" "-i" "-f" "/etc/sysctl.conf" ];
    };

  };
}
