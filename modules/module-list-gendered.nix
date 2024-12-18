nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then [
  ./system/boot/loader/stand-freebsd
  ./system/boot/init/portable/freebsd.nix
  ./system/boot/init/freebsd-rc.nix
] else
  throw "Unsupported target platform ${hostPlatform.system}"
