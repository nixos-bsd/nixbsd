nixpkgsPath:
let extPath = "${nixpkgsPath}/nixos/modules";
in [
  "${extPath}/programs/bash/bash.nix"
  "${extPath}/programs/environment.nix"
  "${extPath}/programs/less.nix"
  ./activation/activation-script.nix
  ./activation/etc-activation.nix
  ./activation/users-groups.nix
  ./build.nix
  ./config/shells-environment.nix
  ./config/system-environment.nix
  ./config/system-path.nix
  ./misc/assertions.nix
  ./misc/extra-arguments.nix
  ./misc/ids.nix
  ./misc/meta.nix
  ./misc/nixpkgs.nix
  ./top-level.nix
]
