{
    lib,
    config,
    pkgs,
    ...
}:
let cfg = config.boot.firstboot;
in
{
    options.boot.firstboot = {
        enable = lib.mkEnableOption "adding a /firstboot file to newly created systems" // { default = true; };
    };
    config = lib.mkIf cfg.enable {
        freebsd.rc.conf.firstboot_sentinel = lib.mkIf pkgs.stdenv.hostPlatform.isFreeBSD "/firstboot";
        virtualisation.vmVariant.virtualisation.extraRootContents = [{
            target = "/firstboot";
            source = builtins.toFile "firstboot" "";
        }];
    };
}
