{ lib, pkgs, config, ... }:

{
  options.programs.passwd.enable = lib.mkEnableOption "the utility for changing passwords" // {
    default = true;
  };

  config = lib.mkIf config.programs.passwd.enable {
    security.wrappers.passwd = {
      setuid = true;
      owner = "root";
      group = "root";
      source = lib.getExe pkgs.freebsd.passwd;
    };

    security.pam.services.passwd.text = ''
      password	required	pam_unix.so		no_warn try_first_pass nullok
    '';
  };
}
