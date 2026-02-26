{
    lib,
    config,
    pkgs,
    ...
}:
let cfg = config.services.wpa_supplicant;
    interfaces = lib.attrValues config.networking.interfaces;
    wlanNames = lib.map (i: i.name) (lib.filter (i: i.wlandev != null) interfaces);
    anyWlan = (builtins.length wlanNames) > 0;
    wlanFlags = (lib.lists.flatten (lib.strings.intersperse "-N" (lib.map (n: ["-i" n]) wlanNames)));
in {
    options.services.wpa_supplicant = {
        enable = (lib.mkEnableOption "wpa_supplicant") // { default = true; };
        package = lib.mkPackageOption pkgs ["freebsd" "wpa_supplicant"] {};
        configFile = lib.mkOption {
            type = lib.types.str;
            description = "Filepath to use for the wpa_supplicant configuation";
            default = "/etc/wpa_supplicant.conf";
        };
    };
    config = lib.mkIf (cfg.enable && anyWlan) {
        # this can't be named wpa_supplicant because default entries in rc.conf will mess with settings
        init.services.wpa_supplicant_all = {
            description = "WPA Supplicant";
            before = [ "NETWORKING" ];
            startType = "foreground";
            startCommand = ["${lib.getBin cfg.package}/bin/wpa_supplicant" "-c" cfg.configFile] ++ wlanFlags;
        };
    };
}
