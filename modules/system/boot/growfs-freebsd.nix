{
    pkgs,
    config,
    lib,
    ...
}:
let cfg = config.services.growfs;
path = with pkgs; with freebsd; [
    sysctl
    gawk
    gnugrep
    geom
    mount
    zfs
    bin
    growfs
];
in {
    options.services.growfs = {
        enable = lib.mkEnableOption "growfs, a service to expand disk images to fit their disk on first boot" // { default = true; };
        addSwap = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = 0;
            description = ''
                Whether to add a swap partition during growfs.

                0 means do not add a swap partition.
                null means add with default size according to the system's RAM size. See growfs(7) for details.
                any other number means create a partition of that size in bytes, even if another swap partition exists.
            '';
        };
    };
    config = lib.mkIf cfg.enable {
        freebsd.rc.services.growfs.script = pkgs.runCommand "growfs" {} ''
            cat >$out <<EOF
            #!${pkgs.runtimeShell}
            export PATH="${lib.makeBinPath path}"
            EOF
            tail -n +2 ${pkgs.freebsd.rc.services}/etc/rc.d/growfs >>$out
            chmod +x $out
        '';
        freebsd.rc.conf.growfs_swap_size = "${lib.optionalString (cfg.addSwap != null) (builtins.toString cfg.addSwap)}";
        boot.firstboot.enable = true;
    };
}
