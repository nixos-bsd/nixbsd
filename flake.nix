{
  inputs = {
    nixpkgs.url = "github:rhelmot/nixpkgs/freebsd-staging";
    utils.url = "github:numtide/flake-utils";
    nix = {
      url = "github:rhelmot/nix/freebsd-staging";
      inputs.nixpkgs.follows = "nixpkgs";
      # We don't need another nixpkgs clone, it won't evaluate anyway
      inputs.nixpkgs-regression.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://attic.mildlyfunctional.gay/nixbsd" ];
    extra-trusted-public-keys =
      [ "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc=" ];
  };

  outputs = { self, nixpkgs, utils, nix }:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-freebsd" ];
      configBase = ./configurations;
      makeSystem = module: self.lib.nixbsdSystem { modules = [ module ]; };
    in {
      lib.nixbsdSystem = args:
        import ./lib/eval-config.nix (args // {
          inherit (nixpkgs) lib;
          nixpkgsPath = nixpkgs.outPath;
          specialArgs = { nixFlake = nix; } // (args.specialArgs or { });
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
              # Building the qcow2 is fast, but is a big upload which takes a lot of cache space
              # Only include the packages that are needed
              # TODO: @artemist: make this automatic
              rootPaths = map (pkg: pkg.drvPath)
                extended.config.system.build.vmImageRunner.passthru.saveDeps;
            };
            inherit (extended) pkgs;
          };
        pkgs = import nixpkgs { inherit system; };
      in {
        packages = lib.mapAttrs'
          (name: value: lib.nameValuePair "${name}" (makeImage value))
          self.nixosConfigurations;

        formatter = pkgs.nixfmt;
      }));
}
