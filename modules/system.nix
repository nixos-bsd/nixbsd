{ lib, ... }: with lib; {
  imports = [
    ./top-level.nix
    ./activation.nix
  ];
}
