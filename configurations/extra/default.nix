{ pkgs, ... }: {
  imports = [ ../base/default.nix ];

  networking.hostName = "nixbsd-extra";
  environment.systemPackages = with pkgs; [ nix-top tmux vim ];
}
