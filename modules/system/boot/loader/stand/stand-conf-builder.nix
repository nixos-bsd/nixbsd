{ pkgs }:

pkgs.substituteAll {
  src = ./stand-conf-builder.sh;
  isExecutable = true;
  path = [pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.jq];
  stand = pkgs.freebsd.stand-efi;
  loader_script = ./nixbsd-loader.lua;
  inherit (pkgs) bash;
}
