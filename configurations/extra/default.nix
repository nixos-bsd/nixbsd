{ pkgs, ... }: {
  imports = [ ../base/default.nix ];
  networking.hostName = "nixbsd-extra";

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  environment.systemPackages = with pkgs; [
    gitMinimal
    htop
    nix-top
    tmux
    unzip
    vim
    zip
  ];
}
