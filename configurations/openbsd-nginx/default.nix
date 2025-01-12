{ pkgs, ... }: {
  imports = [ ../openbsd-base/default.nix ];

  services.nginx = {
    enable = true;
    virtualHosts."localhost" = {
      default = true;
      root = ./.;
    };
  };
}
