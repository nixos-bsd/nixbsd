nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then
  [
    ./system/boot/init/portable/freebsd.nix
    ./system/boot/loader/stand-freebsd
  ]
else if hostPlatform.isOpenBSD then
  [
    ./system/boot/loader/stand-openbsd
  ]
else
  throw "Unsupported target platform ${hostPlatform.system}"
