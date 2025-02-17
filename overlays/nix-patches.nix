final': prev': {
  nixVersions = prev'.nixVersions.extend (final: prev: {
    nix_2_24 = prev.nix_2_24.overrideAttrs {
      patches = [ ./nix-openbsd-pty.patch ];
    };
  });
}
