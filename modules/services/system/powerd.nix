{
    lib,
    pkgs,
    config,
    ...
}:
let cfg = config.services.powerd;
in {
    options.services.powerd = {
        enable = lib.mkEnableOption "Daemon to monitor power status and adjust CPU performance";
        package = lib.mkPackageOption pkgs ["freebsd" "powerd"];
    };

    config = lib.mkIf cfg.enable {
        init.services.powerd = {
            description = "Daemon to monitor power status and adjust CPU performance";
            startCommand = [ "${lib.getExe cfg.package}" ];
            startType = "forking";
            dependencies = [ "DAEMON" ];
            before = [ "LOGIN" ];
        };
    };
}
