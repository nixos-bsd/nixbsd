{
  inputs = {
    nixpkgs.url = "github:nixos-bsd/nixpkgs/openbsd-phase1-split";
  };

  nixConfig = {
    extra-substituters = [ "https://attic.mildlyfunctional.gay/nixbsd" ];
    extra-trusted-public-keys = [ "nixbsd:gwcQlsUONBLrrGCOdEboIAeFq9eLaDqfhfXmHZs1mgc=" ];
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      makePkgs =
        system:
        import nixpkgs {
          inherit system;
        };
      forAllSystems = f: lib.genAttrs lib.systems.flakeExposed (system: f (makePkgs system));
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
      packages = forAllSystems (pkgs: rec {
        demo = pkgs.callPackage ./demo.nix { };
        default = demo;
      });
    };

}
