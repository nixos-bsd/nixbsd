{ pkgs, lib, config, ... }:
{
  config = lib.mkIf config.xdg.mime.enable {
    system.installerDependencies = with pkgs; [
      desktop-file-utils
      shared-mime-info
    ];
  };
}
