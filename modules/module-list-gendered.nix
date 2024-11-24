nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then
  [ ./system/boot/loader/stand ]
else
  throw "Unsupported target platform ${hostPlatform.system}"
