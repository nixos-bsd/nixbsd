nixpkgsPath:
let extPath = "${nixpkgsPath}/nixos/modules";
in [
  "${extPath}/config/shells-environment.nix"
  "${extPath}/config/system-environment.nix"
  "${extPath}/misc/assertions.nix"
  "${extPath}/misc/ids.nix"
  "${extPath}/misc/meta.nix"
  "${extPath}/misc/nixpkgs.nix"
  "${extPath}/programs/bash/bash-completion.nix"
  "${extPath}/programs/bash/bash.nix"
  "${extPath}/programs/environment.nix"
  "${extPath}/programs/less.nix"
  "${extPath}/system/boot/loader/efi.nix"
  "${extPath}/system/etc/etc-activation.nix"
  ./activation/activation-script.nix
  ./activation/top-level.nix
  ./activation/users-groups.nix
  ./config/system-path.nix
  ./misc/extra-arguments.nix
  ./security/wrappers/default.nix
  ./system/boot/kernel.nix
]
