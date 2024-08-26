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
    sys = prev.sys.override {
      extraConfig = ''
        device p9fs
        device virtio_p9fs
      '';
    };
  });
}
