{
  inputs = {
    nixpkgs.url = "github:rhelmot/nixpkgs/freebsd-staging";
    utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    # extra-substituters = [ "https://attic.mildlyfunctional.gay/nixbsd" ];
    # extra-trusted-public-keys = [ "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc=" ];
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
          let
            extended = conf.extendModules {
              modules = [{ config.nixpkgs.buildPlatform = system; }];
            };
          in extended.config.system.build // {
            # appease `nix flake show`
            type = "derivation";
            name = "system-build";

            closureInfo = extended.pkgs.closureInfo {
              rootPaths = [ extended.config.system.build.toplevel.drvPath ];
            };
            vmImageRunnerClosureInfo = extended.pkgs.closureInfo {
              rootPaths =
                [ extended.config.system.build.vmImageRunner.drvPath ];
            };
            inherit (extended) pkgs;
          };
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = lib.mapAttrs'
          (name: value: lib.nameValuePair "${name}" (makeImage value))
          self.nixosConfigurations;

        formatter = pkgs.nixfmt;
      }));
}
