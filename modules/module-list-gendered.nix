nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then
  [
    ./config/i18n-freebsd.nix
    ./config/user-class.nix
    ./progarms/services-mkdb.nix
    ./programs/shutdown-freebsd.nix
    ./system/boot/init/portable/freebsd.nix
    ./system/boot/loader/stand-freebsd
  ]
else if hostPlatform.isOpenBSD then
  [
    ./programs/shutdown-openbsd.nix
    ./system/activation/top-level-openbsd.nix
    ./system/boot/loader/stand-openbsd
  ]
else
  throw "Unsupported target platform ${hostPlatform.system}"
