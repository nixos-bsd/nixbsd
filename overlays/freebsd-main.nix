final': prev': {
  freebsd = prev'.freebsd.overrideScope (final: prev: {
    patchesRoot = ../patchsets/15.0;
    versionData = {
      branch = "CURRENT";
      major = 15;
      minor = 0;
      reldate = "1500027";
      release = "15.0-CURRENT";
      revision = "15.0";
      type = "FreeBSD";
      version = "FreeBSD 15.0-CURRENT";
    };
    sourceData = {
      rev = "8ea6c115409450ff58a8c6b5e818319d181c6bff";
      hash = "sha256-1rjZYEx1lP4nPn0dbBpqNWTh19QaPL68Qf92Luf+y3w=";
    };

    compat = prev.compat.override {
      extraSrc = [
        "sys/sys/md4.h"
      ];
    };
    sys = (prev.sys.override {
      extraConfig = ''
        options P9FS
        device virtio_p9fs
        options UNIONFS
        options NULLFS
      '';
    }).overrideAttrs (prev'': {
      hardeningDisable = prev.sys.hardeningDisable ++ [ "fortify" ];

      # sketchy... if this breaks, we need a patch
      XARGS = "${final.buildFreebsd.xargs-j}/bin/xargs-j";
      XARGS_J = "";

      # there's some unused functions in the zfs stuff
      preBuild = (prev''.preBuild or "") + ''
        export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-unused-function"
      '';
    });

    libsys = final.callPackage ({mkDerivation, include}: mkDerivation {
      path = "lib/libsys";
      extraPaths = [
        "sys/sys"
        "lib/libc/string"
        "lib/libc/include"
        "lib/libc/Versions.def"
      ];
      noLibc = true;
      buildInputs = [
        include
      ];
      preBuild = ''
        mkdir -p $BSDSRCDIR/lib/libsys/$MACHINE_CPUARCH
        ln -s $BSDSRCDIR/lib/libsys/*.h $BSDSRCDIR/lib/libsys/$MACHINE_CPUARCH
      '';
    }) {};

    libprocstat = (prev.libprocstat.override {
      extraSrc = [ "sys/compat/linuxkpi/common" ];
    }).overrideAttrs {
      hardeningDisable = [ "fortify" ];
    };

    libcMinimal = (prev.libcMinimal.override {
      extraSrc = ["lib/libsys"];
    }).overrideAttrs (prev'': {
      OPT_LIBC_MALLOC = "jemalloc";
      buildInputs = prev''.buildInputs ++ [final.libsys];
    });

    libc = prev.libc.override {
      extraModules = [ final.libprocstat ];
    };

    rc = prev.rc.overrideAttrs {
      postPatch = prev.rc.postPatch + ''
        substituteInPlace "$BSDSRCDIR/libexec/rc/Makefile" --replace-fail /libexec $out/libexec
      '';
    };

    stand-efi = final.callPackage ./stand-efi.nix {};
    kldxref = final.callPackage ./kldxref.nix {};

    libmd = (prev.libmd.override {
      extraSrc = [
        "sys/kern"
        "lib/libc/Versions.def"
      ];
    }).overrideAttrs (prev'': {
      MK_TESTS = "no";
    });

    rtld-elf = (prev.rtld-elf.override {
      extraSrc = [ "lib/libsys" ];
    }).overrideAttrs (prev'': {
      buildInputs = prev''.buildInputs ++ [ final.libsys ];
      hardeningDisable = [ "stackprotector" "fortify" ];
    });

    libcrypt = prev.libcrypt.overrideAttrs (prev'': {
      buildInputs = prev''.buildInputs ++ [ final.libmd ];
    });

    libdl = prev.libdl.overrideAttrs (prev'': {
      buildInputs = prev''.buildInputs ++ [ final.libsys ];
    });

    libthr = (prev.libthr.override {
      extraSrc = [ "lib/libsys" ];
    }).overrideAttrs (prev'': {
      buildInputs = prev''.buildInputs ++ [ final.libsys ];
    });

    librt = prev.librt.overrideAttrs (prev'': {
      buildInputs = prev''.buildInputs ++ [ final.libsys ];
    });
  });
}
