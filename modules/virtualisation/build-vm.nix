{ config, extendModules, lib, ... }:
let

  inherit (lib) mkOption;

  vmVariant = extendModules { modules = [ ./qemu-vm.nix ]; };

in {
  options = {
    virtualisation.vmVariant = mkOption {
      description = ''
        Machine configuration to be added for the vm script produced by `nixos-rebuild build-vm`.
      '';
      inherit (vmVariant) type;
      default = { };
      visible = "shallow";
    };
  };

  config = {
    system.build = {
      vm = lib.mkDefault config.virtualisation.vmVariant.system.build.vm;
      systemImage =
        lib.mkDefault config.virtualisation.vmVariant.system.build.systemImage;
    };
  };

  # uses extendModules
  meta.buildDocsInSandbox = false;
}
