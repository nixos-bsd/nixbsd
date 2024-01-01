{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-freebsd14";

  users.users.root.initialPassword = "toor";
}
