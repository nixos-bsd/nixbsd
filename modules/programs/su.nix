{ lib, pkgs, config, ... }:

{
  options.programs.su.enable = lib.mkEnableOption "the utility for user hotswap" // {
    default = true;
  };

  config = lib.mkIf config.programs.su.enable {
    security.wrappers.su = {
      setuid = true;
      owner = "root";
      group = "root";
      source = lib.getExe pkgs.freebsd.su;
    };

    security.pam.services.su.text = ''
      # auth
      auth		sufficient	pam_rootok.so		no_warn
      auth		sufficient	pam_self.so		no_warn
      auth		requisite	pam_group.so		no_warn group=wheel root_only fail_safe ruser
      auth		include		system

      # account
      account		include		system

      # session
      session		required	pam_permit.so
    '';
  };
}
