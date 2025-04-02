{ accountsservice
, stdenv
, buildPackages
, glib
, gobject-introspection
, python3
, wrapGAppsNoGuiHook
, lib
, withIntrospection ?
    lib.meta.availableOn stdenv.hostPlatform gobject-introspection
    && stdenv.hostPlatform.emulatorAvailable buildPackages
}:

python3.pkgs.buildPythonApplication {
  name = "set-session";

  format = "other";

  src = ./set-session.py;

  dontUnpack = true;

  strictDeps = false;

  nativeBuildInputs = [
    wrapGAppsNoGuiHook
  ] ++ lib.optionals withIntrospection [
    gobject-introspection
  ];

  buildInputs = [
    accountsservice
    glib
  ];

  propagatedBuildInputs = with python3.pkgs; [
    ordered-set
    pygobject3
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/set-session
    chmod +x $out/bin/set-session
  '';

  meta = with lib; {
    maintainers = with maintainers; [ ] ++ teams.pantheon.members;
  };
}
