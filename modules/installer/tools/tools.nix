# This module generates nixos-install, nixos-rebuild,
# nixos-generate-config, etc.

{ config, lib, pkgs, ... }:

with lib;

let
  makeProg = args:
    pkgs.substituteAll (args // {
      dir = "bin";
      isExecutable = true;
      nativeBuildInputs = [ pkgs.installShellFiles ];
      postInstall = ''
        installManPage ${args.manPage}
      '';
    });

  nixos-install = makeProg {
    name = "nixos-install";
    src = ./nixos-install.sh;
    inherit (pkgs) runtimeShell;
    hostPlatform = pkgs.stdenv.hostPlatform.system;
    nix = config.nix.package.out;
    path = makeBinPath ([ pkgs.jq nixos-enter ] ++ optionals pkgs.stdenv.hostPlatform.isFreeBSD [ pkgs.freebsd.bin ]);
    manPage = ./manpages/nixos-install.8;
    makedev = if pkgs.stdenv.hostPlatform.isOpenBSD then lib.getExe pkgs.openbsd.makedev else "MAKEDEV";
  };

  nixos-rebuild = makeProg {
    name = "nixos-rebuild";
    src = ./nixos-rebuild.sh;
    inherit (pkgs) runtimeShell;
    nix = config.nix.package.out;
    path = makeBinPath ([
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.jq
    ] ++ optionals pkgs.stdenv.hostPlatform.isFreeBSD [
      pkgs.freebsd.bin
    ]);
    manPage = ./manpages/nixos-rebuild.8;
  };

  nixos-version = makeProg {
    name = "nixos-version";
    src = ./nixos-version.sh;
    inherit (pkgs) runtimeShell;
    inherit (config.system.nixos) version codeName revision;
    inherit (config.system) configurationRevision;
    json = builtins.toJSON ({
      nixosVersion = config.system.nixos.version;
    } // optionalAttrs (config.system.nixos.revision != null) {
      nixpkgsRevision = config.system.nixos.revision;
    } // optionalAttrs (config.system.configurationRevision != null) {
      configurationRevision = config.system.configurationRevision;
    });
    manPage = ./manpages/nixos-version.8;
  };

  nixos-enter = makeProg {
    name = "nixos-enter";
    src = ./nixos-enter.sh;
    inherit (pkgs) runtimeShell;
    hostPlatform = pkgs.stdenv.hostPlatform.system;
    path = makeBinPath (optionals pkgs.stdenv.hostPlatform.isFreeBSD [ pkgs.freebsd.bin ]);
    manPage = ./manpages/nixos-enter.8;
  };

in {

  options.system.disableInstallerTools = mkOption {
    internal = true;
    type = types.bool;
    default = false;
    description = ''
      Disable nixos-rebuild, nixos-generate-config, nixos-installer
      and other NixOS tools. This is useful to shrink embedded,
      read-only systems which are not expected to be rebuild or
      reconfigure themselves. Use at your own risk!
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (config.nix.enable && !config.system.disableInstallerTools) {
      environment.systemPackages =
        [ nixos-install nixos-rebuild nixos-version nixos-enter ];
    })

    # These may be used in auxiliary scripts (ie not part of toplevel), so they are defined unconditionally.
    ({
      system.build = { inherit nixos-install nixos-rebuild nixos-enter; };
      system.installerDependencies = [ pkgs.installShellFiles ];
    })
  ];

}
