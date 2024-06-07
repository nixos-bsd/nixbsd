{
  inputs = {
    nixpkgs.url = "github:rhelmot/nixpkgs/staging-test";
    utils.url = "github:numtide/flake-utils";
    nix = {
      url = "github:rhelmot/nix/freebsd-staging";
      inputs.nixpkgs.follows = "nixpkgs";
      # We don't need another nixpkgs clone, it won't evaluate anyway
      inputs.nixpkgs-regression.follows = "nixpkgs";
    };
    mini-tmpfiles = {
      url = "github:nixos-bsd/mini-tmpfiles";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://attic.mildlyfunctional.gay/nixbsd" ];
    extra-trusted-public-keys =
      [ "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc=" ];
  };

  outputs = { self, nixpkgs, utils, nix, mini-tmpfiles }:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-freebsd" ];
      configBase = ./configurations;
      makeSystem = name: module:
        self.lib.nixbsdSystem {
          modules = [ module { networking.hostName = "nixbsd-${name}"; } ];
        };
    in {
      lib.nixbsdSystem = args:
        import ./lib/eval-config.nix (args // {
          inherit (nixpkgs) lib;
          nixpkgsPath = nixpkgs.outPath;
          specialArgs = {
            nixFlake = nix;
            mini-tmpfiles-flake = mini-tmpfiles;
          } // (args.specialArgs or { });
        } // lib.optionalAttrs (!args ? system) { system = null; });

      nixosConfigurations =
        lib.mapAttrs (name: _: makeSystem name (configBase + "/${name}"))
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
            vmClosureInfo = extended.pkgs.closureInfo {
              rootPaths = [ extended.config.system.build.vm.drvPath ];
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
