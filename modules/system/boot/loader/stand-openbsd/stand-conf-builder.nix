{ pkgs }:

pkgs.substituteAll {
  src = ./stand-conf-builder.sh;
  isExecutable = true;
  path = [
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.jq
  ];
  inherit (pkgs) bash;
}
