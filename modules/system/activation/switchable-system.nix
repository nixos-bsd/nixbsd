{ config, lib, pkgs, ... }:

{

  options = {
    system.switch.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to include the capability to switch configurations.

        Disabling this makes the system unable to be reconfigured via `nixos-rebuild`.

        This is good for image based appliances where updates are handled
        outside the image. Reducing features makes the image lighter and
        slightly more secure.
      '';
    };
  };

  config = lib.mkIf config.system.switch.enable {
    # TODO localeArchive
    system.activatableSystemBuilderCommands = ''
      mkdir $out/bin
      substitute ${
        ./switch-to-configuration.sh
      } $out/bin/switch-to-configuration \
        --subst-var out \
        --subst-var-by toplevel ''${!toplevelVar} \
        --subst-var-by coreutils "${pkgs.coreutils}" \
        --subst-var-by diffutils "${pkgs.diffutils}" \
        --subst-var-by rcorder "${pkgs.freebsd.rcorder}" \
        --subst-var-by distroId ${
          lib.escapeShellArg config.system.nixos.distroId
        } \
        --subst-var-by installBootLoader ${
          lib.escapeShellArg config.system.build.installBootLoader
        } \
        --subst-var-by bash "${pkgs.bash}" \
        --subst-var-by shell "${pkgs.bash}/bin/sh" \
        --subst-var-by pathLocale "${config.i18n.freebsdLocales}/share/locale" \
        ;

      chmod +x $out/bin/switch-to-configuration
      ${lib.optionalString
      (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) ''
        # TODO syntax checking
      ''}
    '';
  };

}
