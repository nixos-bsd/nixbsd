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
  nixosVersion ? "0",
  nixosCodeName ? null,
  nixosRevision ? "nobody",
  configurationRevision ? "never",
}:
let
  makeProg = args:
    replaceVarsWith (args // {
      dir = "bin";
      isExecutable = true;
      nativeBuildInputs = [ installShellFiles ];
      postInstall = ''
        installManPage ${args.manPage}
      '';
    });
in rec {

  nixos-install = makeProg {
    name = "nixos-install";
    src = ./nixos-install.sh;
    manPage = ./manpages/nixos-install.8;
    replacements = {
      inherit runtimeShell nix;
      hostPlatform = stdenv.hostPlatform.system;
      path = lib.makeBinPath (
        [
          jq
          nixos-enter
        ] ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
          freebsd.bin
        ] ++ lib.optionals (!stdenv.hostPlatform.isFreeBSD) [
          socat
        ] ++ lib.optionals stdenv.hostPlatform.isOpenBSD [
          openbsd.mknod
        ]);
      makedev = if stdenv.hostPlatform.isOpenBSD then lib.getExe openbsd.makedev else "MAKEDEV";
    };
  };

  nixos-rebuild = makeProg {
    name = "nixos-rebuild";
    src = ./nixos-rebuild.sh;
    manPage = ./manpages/nixos-rebuild.8;
    replacements = {
      inherit runtimeShell nix;
      path = lib.makeBinPath ([
        coreutils
        gnused
        gnugrep
        jq
      ] ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
        freebsd.bin
      ]);
    };
  };

  nixos-version = makeProg {
    name = "nixos-version";
    src = ./nixos-version.sh;
    manPage = ./manpages/nixos-version.8;
    replacements = {
      inherit runtimeShell;
      version = nixosVersion;
      codeName = nixosCodeName;
      revision = nixosRevision;
      json = builtins.toJSON ({
        inherit nixosVersion;
      } // lib.optionalAttrs (nixosRevision != null) {
        inherit nixosRevision;
      } // lib.optionalAttrs (configurationRevision != null) {
        inherit configurationRevision;
      });
    };
  };

  nixos-enter = makeProg {
    name = "nixos-enter";
    src = ./nixos-enter.sh;
    manPage = ./manpages/nixos-enter.8;
    replacements = {
      inherit runtimeShell;
      hostPlatform = stdenv.hostPlatform.system;
      path = lib.makeBinPath (lib.optionals stdenv.hostPlatform.isFreeBSD [ freebsd.bin ]);
    };
  };
}
