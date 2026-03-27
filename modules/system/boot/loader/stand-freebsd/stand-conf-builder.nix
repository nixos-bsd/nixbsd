{
  pkgs,
  stand-efi,
  localScript ? null,
}:

pkgs.replaceVarsWith {
  src = ./stand-conf-builder.sh;
  isExecutable = true;
  replacements = {
    path = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.jq
    ];
    stand = stand-efi;
    loader_script = "${./nixbsd-loader.lua}";
    inherit (pkgs) bash;

    inherit localScript;

    overridesDir = "${./overrides}";
  };
}
