{
  inputs = {
    nixpkgs.url = "github:nixos-bsd/nixpkgs/nixbsd-dev-new";
    mini-tmpfiles = {
      url = "github:nixos-bsd/mini-tmpfiles";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  nixConfig = {
    extra-substituters = [
      "https://nixcache.reflex-frp.org" 
      "https://attic.mildlyfunctional.gay/nixbsd"
    ];
    extra-trusted-public-keys = [
      "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI="
      "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc="
    ];
  };

  outputs = { self, nixpkgs, mini-tmpfiles, ... }:
    let
      inherit (nixpkgs) lib;

      makePkgs = system: import nixpkgs { inherit system; };
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      configBase = ./configurations;
      makeSystem = name: module:
        self.lib.nixbsdSystem {
          modules = [ module { networking.hostName = "nixbsd-${name}"; } ];
        };

      makeImage = buildPlatform: conf:
        let
          extended = conf.extendModules {
            modules = [{
              config.nixpkgs.buildPlatform = buildPlatform;
            }];
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
          inherit (extended) pkgs config;
        };
    in {
      lib.nixbsdSystem = args:
        import ./lib/eval-config.nix (args // {
          inherit (nixpkgs) lib;
          nixpkgsPath = nixpkgs.outPath;
          specialArgs = {
            mini-tmpfiles-flake = mini-tmpfiles;
          } // (args.specialArgs or { });
        } // lib.optionalAttrs (!args ? system) { system = null; });

      nixosConfigurations =
        lib.mapAttrs (name: _: makeSystem name (configBase + "/${name}"))
        (builtins.readDir configBase);

      packages = forAllSystems (system:
        lib.mapAttrs (name: makeImage system) self.nixosConfigurations);

      formatter = forAllSystems (system: (makePkgs system).nixfmt-rfc-style);

      hydraJobs = {inherit (self.packages.x86_64-linux.openbsd-nginx) vm systemImage;};
    };
}
