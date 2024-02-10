{ config, lib, ... }:
let inherit (lib) stringAfter;
in {

  config = {
    system.activationScripts.etc = stringAfter [ "users" "groups" ]
      config.system.build.etcActivationCommands;
  };
}
