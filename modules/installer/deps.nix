{ pkgs, config, lib, ... }:
{
  options.system.includeInstallerDependencies = lib.mkOption {
    type = lib.types.bool;
    description = "Enable this to add to the system the derivations necessary for installing a system without building software on that system; i.e. build it beforehand.";
    default = !config.nixpkgs.fakeNative;
    defaultText = "!config.nixpkgs.fakeNative";
  };
  # TODO: is it possible to automatically compute this?
  options.system.installerDependencies = lib.mkOption {
    type = lib.types.listOf lib.types.pathInStore;
    description = "Add dependencies to this list to bundle them in with an installer image (if system.bundleInstallerDependencies is enabled).";
    default = [];
  };

  config = lib.mkIf config.system.includeInstallerDependencies {
    system.installerDependencies = [
      config.nixpkgs.fakeNativePkgs.stdenv
    ];
    system.extraDependencies = config.system.installerDependencies;
  };
}
