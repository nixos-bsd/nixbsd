final: prev: {
  freebsd = prev.freebsd.overrideScope (final: prev: {
    patchesRoot = ../patchsets/15.0;
    versionData = {
      branch = "CURRENT";
      major = 15;
      minor = 0;
      reldate = "1500023";
      release = "15.0-CURRENT";
      revision = "15.0";
      type = "FreeBSD";
      version = "FreeBSD 15.0-CURRENT";
    };
    sourceData = {
      rev = "ef3f8aa0a0492487ac7db839de078b1913f61b4c";
      hash = "sha256-75xz2Seq2adetbgpUUs1OBGJ+5L/jMqqzS2uAosqISI=";
    };

    sys = (prev.sys.override {
      extraConfig = ''
        device p9fs
        device virtio_p9fs
      '';
    }).overrideAttrs {
      hardeningDisable = prev.sys.hardeningDisable ++ [ "fortify" ];

      # sketchy... if this breaks, we need a patch
      XARGS = "${final.buildFreebsd.xargs-j}/bin/xargs-j";
      XARGS_J = "";
    };

    libc = (prev.libc.overrideFilterSrc {
      addPaths = ["lib/libsys"];
    }).overrideAttrs {
      OPT_LIBC_MALLOC = "jemalloc";
      preBuild = prev.libc.preBuild + ''
        mkdir -p $BSDSRCDIR/lib/libsys/$MACHINE_CPUARCH
        ln -s $BSDSRCDIR/lib/libsys/*.h $BSDSRCDIR/lib/libsys/$MACHINE_CPUARCH
        make -C $BSDSRCDIR/lib/libsys $makeFlags
        make -C $BSDSRCDIR/lib/libsys $makeFlags install
      '';
      # fortify flag includes some ssp stuff deep in the libprocstat build. remove this if we split that out to another derivation!
      hardeningDisable = prev.libc.hardeningDisable ++ [ "fortify" ];
    };

    rc = prev.rc.overrideAttrs {
      postPatch = prev.rc.postPatch + ''
        substituteInPlace "$BSDSRCDIR/libexec/rc/Makefile" --replace-fail /libexec $out/libexec
      '';
    };

    stand-efi = prev.stand-efi.overrideAttrs {
      hardeningDisable = prev.stand-efi.hardeningDisable ++ [ "fortify" ];
    };
  });
}
