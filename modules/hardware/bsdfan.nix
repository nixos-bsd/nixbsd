{
    pkgs,
    config,
    lib,
    ...
}:
let cfg = config.hardware.bsdfan;
in {
    options.hardware.bsdfan = {
        enable = lib.mkEnableOption "Fan control for thinkpads";
        package = lib.mkPackageOption pkgs ["freebsd" "bsdfan"] {};
        config = lib.mkOption {
            description = "bsdfan.conf configuration file path";
            type = lib.types.pathInStore;
            default = "${cfg.package}/etc/bsdfan.conf";
        };
    };
    config = lib.mkIf cfg.enable {
        init.services.bsdfan = {
            description = "Fan control for thinkpads";
            dependencies = [ "DAEMON" ];

            startType = "foreground";
            startCommand = [ (lib.getExe pkgs.freebsd.bsdfan) ];
        };

        environment.etc."bsdfan.conf".source = cfg.config;
    };
}
