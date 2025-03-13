{ pkgs, ... }: {
  imports = [ ../base/default.nix ];

  environment.systemPackages = with pkgs; [
    gitMinimal
    vim
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  boot.enableJails = true;
  jails.immich = {
    config = {
      services.immich.enable = true;
      services.immich.machine-learning.enable = false;
    };
  };
}
