{
    lib,
    config,
    pkgs,
    ...
}:
let cfg = config.services.wpa_supplicant;
in {
    options.services.wpa_supplicant = {
        enable = lib.mkEnableOption "wpa_supplicant";
        package = lib.mkPackageOption pkgs ["freebsd" "wpa_supplicant"] {};
        configFile = lib.mkOption {
            type = lib.types.str;
            description = "Filepath to use for the wpa_supplicant config file";
            default = "/etc/wpa_supplicant.conf";
        };
    };
    config = lib.mkIf cfg.enable {
        freebsd.rc.services.wpa_supplicant.source = "${pkgs.freebsd.rc.services}/etc/rc.d/wpa_supplicant";
        freebsd.rc.conf.wpa_supplicant_program = "${lib.getBin cfg.package}/bin/wpa_supplicant";
        freebsd.rc.conf.wpa_supplicant_conf_file = cfg.configFile;
    };
}
