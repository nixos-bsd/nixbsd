{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-freebsd14";

  # users.users.root.initialPassword = "toor";
  users.users.root.initialHashedPassword = "$6$3nUloJ87IrkLd7gx$231FBM2Xp2XgcmNwDQBvaqmD2LHdRbr3MSRVgi4cC.t5h/KxHxL4zxE4P4SFjUvbWh25di3ANOC5MM9NJV8lV/";
}
