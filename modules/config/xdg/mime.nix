{ pkgs, lib, config, ... }:
{
  config = lib.mkIf config.xdg.mime.enabled {
    system.installerDependencies = with pkgs; [
      desktop-file-utils
      shared-mime-info
    ];
  };
}
