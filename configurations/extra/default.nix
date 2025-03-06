{ pkgs, ... }: {
  imports = [ ../base/default.nix ];

  nix.settings = {
    trusted-users = [ "root" "nixbld" "@wheel" ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  environment.systemPackages = with pkgs; [
    file
    freebsd.truss
    gitMinimal
    htop
    mini-tmpfiles
    tmux
    unzip
    vim
    zip
  ];
}
