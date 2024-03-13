{ pkgs, ... }: {
  imports = [ ../base/default.nix ];

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  environment.systemPackages = with pkgs; [
    file
    freebsd.truss
    gitMinimal
    htop
    mini-tmpfiles
    nix-top
    tmux
    unzip
    vim
    zip
  ];
}
