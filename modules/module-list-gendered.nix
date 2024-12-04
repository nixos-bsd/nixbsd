nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then [
  ./system/boot/loader/stand
  ./system/boot/init/portable/freebsd.nix
] else
  throw "Unsupported target platform ${hostPlatform.system}"
