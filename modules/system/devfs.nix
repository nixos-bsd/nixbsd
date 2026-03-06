{
    config,
    pkgs,
    lib,
    ...
}:
let cfg = config.system.devfs;
in {
    options.system.devfs = {
        useDefaultRulesets = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to include the default devfs rules from FreeBSD upstream";
        };
    };

    config = {
        environment.etc."devfs.rules".source = lib.mkIf cfg.useDefaultRulesets "${pkgs.freebsd.devfs}/etc/devfs.rules";
        freebsd.rc.services.devfs.source = "${pkgs.freebsd.rc.services}/etc/rc.d/devfs";
    };
}
