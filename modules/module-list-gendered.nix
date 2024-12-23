nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then
  [
    ./config/i18n-freebsd.nix
    ./programs/services-mkdb.nix
    ./programs/shutdown-freebsd.nix
    ./services/ttys/getty-freebsd.nix
    ./system/boot/init/portable/freebsd.nix
    ./system/boot/loader/stand-freebsd
  ]
else if hostPlatform.isOpenBSD then
  [
    ./programs/shutdown-openbsd.nix
    ./services/ttys/getty-openbsd.nix
    ./system/activation/top-level-openbsd.nix
    ./system/boot/loader/stand-openbsd
    ./system/boot/init/portable/openbsd.nix
  ]
else
  throw "Unsupported target platform ${hostPlatform.system}"
