{
  inputs = {
    nixpkgs.url = "github:rhelmot/nixpkgs/freebsd-staging";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-freebsd14" ];
      configBase = ./configurations;
      makeSystem = module: self.lib.nixbsdSystem { modules = [ module ]; };
    in {
      lib.nixbsdSystem = args:
        import ./lib/eval-config.nix (args // {
          inherit (nixpkgs) lib;
          nixpkgsPath = nixpkgs.outPath;
        } // lib.optionalAttrs (!args ? system) { system = null; });

      nixosConfigurations =
        lib.mapAttrs (name: _: makeSystem (configBase + "/${name}"))
        (builtins.readDir configBase);
    } // (utils.lib.eachSystem supportedSystems (system:
      let
        makeImage = conf:
          (conf.extendModules {
            modules = [{ config.nixpkgs.buildPlatform = system; }];
          }).config.system.build // {
            type = "derivation";
            name = "system-build";
          };
      in {
        packages = lib.mapAttrs'
          (name: value: lib.nameValuePair "${name}" (makeImage value))
          self.nixosConfigurations;
      }));
}
