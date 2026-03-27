{
  config,
  lib,
  pkgs,
  extendModules, # used for importing upstream image modules
  ...
}:
let
  inherit (lib) types;

  _nixbsdNixpkgsPath = (pkgs.path);

  imageModules = {
    # amazon = (_nixbsdNixpkgsPath + /maintainers/scripts/ec2/amazon-image.nix);
    # azure = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/azure-image.nix);
    # cloudstack = (_nixbsdNixpkgsPath + /maintainers/scripts/cloudstack/cloudstack-image.nix);
    # digital-ocean = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/digital-ocean-image.nix);
    # google-compute = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/google-compute-image.nix);
    # hyperv = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/hyperv-image.nix);
    # linode = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/linode-image.nix);
    # lxc = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/lxc-container.nix);
    # lxc-metadata = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/lxc-image-metadata.nix);
    # oci = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/oci-image.nix);
    # openstack = (_nixbsdNixpkgsPath + /maintainers/scripts/openstack/openstack-image.nix);
    # openstack-zfs = (_nixbsdNixpkgsPath + /maintainers/scripts/openstack/openstack-image-zfs.nix);
    # proxmox = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/proxmox-image.nix);
    # proxmox-lxc = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/proxmox-lxc.nix);
    # qemu-efi = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/disk-image.nix);
    # qemu = {
    #   imports = [ (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/disk-image.nix) ];
    #   image.efiSupport = false;
    # };
    # raw-efi = {
    #   imports = [ (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/disk-image.nix) ];
    #   image.format = "raw";
    # };
    # raw = {
    #   imports = [ (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/disk-image.nix) ];
    #   image.format = "raw";
    #   image.efiSupport = false;
    # };
    # kubevirt = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/kubevirt.nix);
    # vagrant-virtualbox = (
    #   _nixbsdNixpkgsPath + /nixos/modules/virtualisation/vagrant-virtualbox-image.nix
    # );
    # virtualbox = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/virtualbox-image.nix);
    # vmware = (_nixbsdNixpkgsPath + /nixos/modules/virtualisation/vmware-image.nix);

    iso = ../installer/iso-image.nix;
    # iso-installer = (_nixbsdNixpkgsPath + /nixos/modules/installer/cd-dvd/installation-cd-base.nix);
    # sd-card = {
    #   imports =
    #     let
    #       module =
    #         _nixbsdNixpkgsPath
    #         + "/nixos/modules/installer/sd-card/sd-image-${pkgs.targetPlatform.qemuArch}.nix";
    #     in
    #     if builtins.pathExists module then
    #       [ module ]
    #     else
    #       throw "The module ${toString module} does not exist.";
    # };
    # kexec = _nixbsdNixpkgsPath + /nixos/modules/installer/netboot/netboot-minimal.nix;
  };
  imageConfigs = lib.mapAttrs (
    name: module:
    extendModules {
      modules = [ module ];
    }
  ) config.image.modules;
in
{
  options = {
    system.build = {
      images = lib.mkOption {
        type = types.lazyAttrsOf types.raw;
        readOnly = true;
        description = ''
          Different target images generated for this NixOS configuration.
        '';
      };
    };
    image.modules = lib.mkOption {
      type = types.attrsOf types.deferredModule;
      description = ''
        image-specific NixOS Modules used for `system.build.images`.
      '';
    };
  };

  config.image.modules = lib.mkIf (!config.system.build ? image) imageModules;
  config.system.build.images = lib.mkIf (!config.system.build ? image) (
    lib.mapAttrs (
      name: nixos:
      let
        inherit (nixos) config;
        inherit (config.image) filePath;
        builder =
          config.system.build.image
            or (throw "Module for `system.build.images.${name}` misses required `system.build.image` option.");
      in
      lib.recursiveUpdate builder {
        passthru = {
          inherit config filePath;
        };
      }
    ) imageConfigs
  );
}
