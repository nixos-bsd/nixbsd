{ lib, ... }:
{
  config.programs.tmux.withUtempter = lib.mkDefault false;
}
