{
    stdenv,
    lib,
    cmake,
    fetchFromGitHub,
    pkg-config,
    gperf,
    libinotify-kqueue,
    fuse,
    gnum4,
}:
stdenv.mkDerivation {
    pname = "initware";
    version = "0.0.0-2024-08-16";
    src = fetchFromGitHub {
        owner = "InitWare";
        repo = "InitWare";
        rev = "907cebfc4106ea316bfb75509f67c685a45bdb94";
        fetchSubmodules = true;
        hash = "sha256-RxXO9FFcigtmLCPtRlF8SE+tCnWxWqR32WiByGNFCHY=";
    };

    patches = [
        ./standard-funcs.patch
        ./elementsof.patch
    ];

    nativeBuildInputs = [
        cmake
        gperf
        pkg-config
        gnum4
    ];

    buildInputs = [
        libinotify-kqueue
        fuse
    ];

    cmakeFlags = [
        "-DSVC_PKGDIRNAME=systemd"
    ];

    postInstall = ''
      ln -s svcctl $out/bin/systemctl
      ln -s svcctl $out/bin/halt
      ln -s svcctl $out/bin/poweroff
      ln -s svcctl $out/bin/reboot
      ln -s svcctl $out/bin/shutdown
      ln -s svcctl $out/bin/init
      ln -s svcctl $out/bin/runlevel
      ln -s syslogctl $out/bin/journalctl
    '';

    meta = {
        homepage = "https://github.com/InitWare/InitWare";
        license = lib.licenses.lgpl21;
        maintainers = [ lib.maintainers.rhelmot ];
    };
}
