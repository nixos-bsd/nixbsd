{
  lib,
  config,
  options,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatMapAttrs
    mkOption
    types
    concatLists
    mapAttrsToList
    ;

  portable-lib = import "${pkgs.path}/lib/services/lib.nix" { inherit lib; };

  dash =
    before: after:
    if after == "" then
      before
    else if before == "" then
      after
    else
      "${before}-${after}";

  makeEtcFiles =
    prefix: service:
    let
      # Convert configData entries to environment.etc entries
      serviceConfigData = lib.mapAttrs' (name: cfg: {
        name =
          # cfg.path is read only and prefixed with unique service name; see ./config-data-path.nix
          assert lib.hasPrefix "/etc/system-services" cfg.path;
          lib.removePrefix "/etc/" cfg.path;
        value = {
          inherit (cfg) enable source;
        };
      }) (service.configData or { });

      # Recursively process sub-services
      subServiceConfigData = concatMapAttrs (
        subServiceName: subService: makeEtcFiles (dash prefix subServiceName) subService
      ) service.services;
    in
    serviceConfigData // subServiceConfigData;

  makeUnits =
    prefix: service:
    concatMapAttrs (unitName: unitModule: {
      "${dash prefix unitName}" =
        { ... }:
        {
          imports = [ unitModule ];
        };
    }) service.freebsd.rc.services
    // concatMapAttrs (
      subServiceName: subService: makeUnits (dash prefix subServiceName) subService
    ) service.services;

  makeUsers =
    _: service:
    {
      "${service.freebsd.meta.username}" = {
        group = service.freebsd.meta.username;
        home = service.freebsd.meta.dataDir;
        createHome = true;
        isSystemUser = true;
      };
    }
    // (concatMapAttrs makeUsers service.services);

  makeGroups =
    _: service:
    {
      "${service.freebsd.meta.username}" = { };
    }
    // (concatMapAttrs makeGroups service.services);

  modularServiceConfiguration = portable-lib.configure {
    serviceManagerPkgs = pkgs;
    extraRootModules = [
      ./service.nix
      ./config-data-path.nix
    ];

    extraRootSpecialArgs = {
      freebsdPackages = pkgs.freebsd;
    };
  };
in
{
  _class = "nixos";

  options = {
    system.services = mkOption {
      description = ''
        A collection of NixOS [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured as systemd services.
      '';
      type = types.attrsOf modularServiceConfiguration.serviceSubmodule;
      default = { };
      visible = "shallow";
    };
  };

  config = {
    assertions = concatLists (
      mapAttrsToList (
        name: cfg: portable-lib.getAssertions (options.system.services.loc ++ [ name ]) cfg
      ) config.system.services
    );

    warnings = concatLists (
      mapAttrsToList (
        name: cfg: portable-lib.getWarnings (options.system.services.loc ++ [ name ]) cfg
      ) config.system.services
    );

    freebsd.rc.services = concatMapAttrs makeUnits config.system.services;

    environment.etc = concatMapAttrs makeEtcFiles config.system.services;

    users.users = concatMapAttrs makeUsers config.system.services;

    users.groups = concatMapAttrs makeGroups config.system.services;

    systemd.tmpfiles.settings."10-modular-system" = {
      "/var/lib/system-services".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    };
  };
}
