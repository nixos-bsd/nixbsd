{
  lib,
  stdenv,
  replaceVarsWith,
  installShellFiles,
  runtimeShell,
  nix,
  jq,
  socat,
  freebsd,
  openbsd,
  coreutils,
  gnused,
  gnugrep,
  perl,
  config,
  nixosVersion ? "0",
  nixosCodeName ? null,
  nixosRevision ? "nobody",
  configurationRevision ? "never",
}:
let
  makeProg = args:
    replaceVarsWith {
      inherit (args) name src;
      dir = "bin";
      isExecutable = true;
      nativeBuildInputs = [ installShellFiles ];
      postInstall = ''
        installManPage ${args.manPage}
      '';
      replacements = lib.removeAttrs args ["name" "src" "manPage"];
    };
in
rec {
  nixos-generate-config = makeProg {
    name = "nixos-generate-config";
    src = ./nixos-generate-config.pl;

    perl = "${
      perl.withPackages (p: [
        p.FileSlurp
        p.ConfigIniFiles
      ])
    }/bin/perl";
    hostPlatformSystem = stdenv.hostPlatform.system;
    detectvirt = "echo qemu"; # "${config.systemd.package}/bin/systemd-detect-virt";
    inherit (config.system.nixos-generate-config) configuration;
    # xserverEnabled = config.services.xserver.enable;

    manPage = ./manpages/nixos-generate-config.8;
  };

  nixos-install = makeProg {
    name = "nixos-install";
    src = ./nixos-install.sh;
    inherit runtimeShell;
    hostPlatform = stdenv.hostPlatform.system;
    path = lib.makeBinPath (
      [
        jq
        nixos-enter
        nix
      ] ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
        freebsd.bin
      ] ++ lib.optionals (!stdenv.hostPlatform.isFreeBSD) [
        socat
      ] ++ lib.optionals stdenv.hostPlatform.isOpenBSD [
        openbsd.mknod
      ]);
    manPage = ./manpages/nixos-install.8;
    makedev = if stdenv.hostPlatform.isOpenBSD then lib.getExe openbsd.makedev else "MAKEDEV";
  };

  nixos-rebuild = makeProg {
    name = "nixos-rebuild";
    src = ./nixos-rebuild.sh;
    inherit runtimeShell nix;
    path = lib.makeBinPath ([
      coreutils
      gnused
      gnugrep
      jq
    ] ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
      freebsd.bin
    ]);
    manPage = ./manpages/nixos-rebuild.8;
  };

  nixos-version = makeProg {
    name = "nixos-version";
    src = ./nixos-version.sh;
    inherit runtimeShell;
    version = nixosVersion;
    codeName = nixosCodeName;
    revision = nixosRevision;
    json = builtins.toJSON ({
      inherit nixosVersion;
    } // lib.optionalAttrs (nixosCodeName != null) {
      inherit nixosCodeName;
    } // lib.optionalAttrs (nixosRevision != null) {
      inherit nixosRevision;
    } // lib.optionalAttrs (configurationRevision != null) {
      inherit configurationRevision;
    });
    manPage = ./manpages/nixos-version.8;
  };

  nixos-enter = makeProg {
    name = "nixos-enter";
    src = ./nixos-enter.sh;
    inherit runtimeShell;
    hostPlatform = stdenv.hostPlatform.system;
    manPage = ./manpages/nixos-enter.8;
  };
}
