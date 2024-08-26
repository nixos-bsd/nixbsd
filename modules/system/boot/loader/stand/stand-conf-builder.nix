{ pkgs, stand-efi, initmd }:

pkgs.substituteAll {
  src = ./stand-conf-builder.sh;
  isExecutable = true;
  path = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.jq ];
  stand = stand-efi;
  loader_script = ./nixbsd-loader.lua;
  inherit (pkgs) bash;
  initmd = if initmd == null then "" else initmd;
}
