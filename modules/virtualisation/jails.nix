{ lib, pkgs, config, ... }@host:
with lib;
let
  stateDirectory = "/var/lib/nixbsd-jails";
  mkJailConf = name: cfg: pkgs.writeText "jail.${name}.conf" (''
    ${name} {
      path = "${stateDirectory}/${name}";
      host.hostname = "${name}.jail";
      mount.fstab = "${mkFstab name cfg}";
      mount.devfs;
      exec.start = "${pkgs.runtimeShell} ${mkInitScript name cfg}";
      exec.stop = "${pkgs.runtimeShell} ${cfg.config.freebsd.rc.package}/etc/rc.shutdown jail";
      persist;
      sysvmsg = new;
      sysvsem = new;
      sysvshm = new;
  '' + lib.optionalString (!cfg.vnet) ''
      ip4 = inherit;
      ip6 = inherit;
      allow.raw_sockets;
  '' + lib.optionalString cfg.vnet ''
      vnet = new;
  '' + ''
    }
  '');
  mkInitScript = name: cfg: pkgs.writeText "jail.${name}.init" ''
    . ${cfg.config.system.build.toplevel}/activate
    . ${cfg.config.freebsd.rc.package}/etc/rc
  '';
  # TODO toposort
  mkFstab = name: cfg: pkgs.writeText "jail.${name}.fstab" (''
    # Device''\tMountpoint''\tFStype''\tOptions''\tDump''\tPass#
  '' + lib.concatMapStrings (mnt: ''
    ${if mnt.hostPath == null then mnt.mountPoint else mnt.hostPath}''\t${stateDirectory}/${name}${mnt.mountPoint}''\tnullfs''\t${if mnt.isReadOnly then "ro" else "rw"}''\t0''\t2
  '') (lib.attrValues cfg.bindMounts) + lib.concatMapStrings (mnt: ''
    tmpfs''\t${stateDirectory}/${name}/${mnt}''\ttmpfs''\trw''\t0''\t2
  '') cfg.tmpfs);

  bindMountOpts = { name, ... }: {
    options = {
      mountPoint = mkOption {
        example = "/mnt/usb";
        type = types.str;
        description = "Mount point on the container file system.";
      };
      hostPath = mkOption {
        default = null;
        example = "/home/alice";
        type = types.nullOr types.str;
        description = "Location of the host path to be mounted.";
      };
      isReadOnly = mkOption {
        default = true;
        type = types.bool;
        description = "Determine whether the mounted path will be accessed in read-only mode.";
      };
      isFile = mkOption {
        default = false;
        type = types.bool;
        description = "Determine if the bound node is a file or a directory.";
      };
    };
    config = {
      mountPoint = mkDefault name;
    };
  };
in
{
  options = {
    boot.isJail = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether this NixBSD machine is a jail running
        in another NixBSD system.
      '';
    };

    boot.enableJails = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable support for FreeBSD jails. Defaults to true
        (at no cost if jails are not actually used).
      '';
    };

    jails = mkOption {
      type = types.attrsOf (types.submodule (
        { config, options, name, ... }:
        {
          options = {
            config = mkOption {
              description = ''
                A specification of the desired configuration of this
                jail, as a NixOS module.
              '';
              type = lib.mkOptionType {
                name = "Toplevel NixOS config";
                merge = loc: defs: (import ../../lib/eval-config.nix {
                  inherit lib;
                  extraArgs = {
                    inherit (host) lixFlake mini-tmpfiles-flake;
                  };
                  nixpkgsPath = config.nixpkgs;
                  modules =
                    let
                      extraConfig = { options, ... }: {
                        _file = "module at ${__curPos.file}:${toString __curPos.line}";
                        config = {
                          nixpkgs =
                            if options.nixpkgs?hostPlatform
                            then { inherit (host.pkgs.stdenv) hostPlatform buildPlatform; }
                            else { localSystem = host.pkgs.stdenv.buildPlatform; crossSystem = host.pkgs.stdenv.hostPlatform; }
                          ;
                          boot.isJail = true;
                          networking.hostName = mkDefault name;
                          networking.useDHCP = false;
                        };
                      };
                    in [ extraConfig ] ++ (map (x: x.value) defs);
                  prefix = [ "jails" name ];
                  inherit (config) specialArgs;

                  # The system is inherited from the host above.
                  # Set it to null, to remove the "legacy" entrypoint's non-hermetic default.
                  system = null;
                }).config;
              };
            };

            path = mkOption {
              type = types.path;
              example = "/nix/var/nix/profiles/per-jail/webserver";
              description = ''
                As an alternative to specifying
                {option}`config`, you can specify the path to
                the evaluated NixBSD system configuration, typically a
                symlink to a system profile.
              '';
            };

            nixpkgs = mkOption {
              type = types.path;
              default = pkgs.path;
              defaultText = literalExpression "pkgs.path";
              description = ''
                A path to the nixpkgs that provide the modules, pkgs and lib for evaluating the container.

                To only change the `pkgs` argument used inside the container modules,
                set the `nixpkgs.*` options in the container {option}`config`.
                Setting `config.nixpkgs.pkgs = pkgs` speeds up the container evaluation
                by reusing the system pkgs, but the `nixpkgs.config` option in the
                container config is ignored in this case.
              '';
            };

            specialArgs = mkOption {
              type = types.attrsOf types.unspecified;
              default = {};
              description = ''
                A set of special arguments to be passed to NixOS modules.
                This will be merged into the `specialArgs` used to evaluate
                the NixBSD configurations.
              '';
            };

            ### Startup control settings

            ephemeral = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Runs jail in ephemeral mode with the empty root filesystem at boot.
                This way jail will be bootstrapped from scratch on each boot
                and will be cleaned up on shutdown leaving no traces behind.
                Useful for completely stateless, reproducible jails.

                Note that this option might require to do some adjustments to the container configuration,
                e.g. you might want to set
                {var}`systemd.network.networks.$interface.dhcpV4Config.ClientIdentifier` to "mac"
                if you use {var}`macvlans` option.
                This way dhcp client identifier will be stable between the container restarts.

                Note that the container journal will not be linked to the host if this option is enabled.
              '';
            };

            autoStart = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether the container is automatically started at boot-time.
              '';
            };

            restartIfChanged = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether the container should be restarted during a NixBSD
                configuration switch if its definition has changed.
              '';
            };

            timeoutStartSec = mkOption {
              type = types.str;
              default = "1min";
              description = ''
                Time for the container to start. In case of a timeout,
                the container processes get killed.
                See {manpage}`systemd.time(7)`
                for more information about the format.
               '';
            };

            ### Filesystem settings

            bindMounts = mkOption {
              type = with types; attrsOf (submodule bindMountOpts);
              default = {
                "/nix" = { isReadOnly = true; };
                "/etc/resolv.conf" = { isReadOnly = true; isFile = true; };
              };
              example = literalExpression ''
                { "/home" = { hostPath = "/home/alice";
                              isReadOnly = false; };
                }
              '';

              description = ''
                  An extra list of directories that is bound to the container.
                '';
            };

            tmpfs = mkOption {
              type = types.listOf types.str;
              default = [];
              example = [ "/var" ];
              description = ''
                Mounts a set of tmpfs file systems into the container.
                Multiple paths can be specified.
                Valid items must conform to the --tmpfs argument
                of systemd-nspawn. See {manpage}`systemd-nspawn(1)` for details.
              '';
            };

            ### Network settings

            vnet = mkOption {
              type = types.bool;
              default = false;
              description = "Create a virtual network stack for the jail.";
            };
          };
        }));

      default = {};
      example = literalExpression
        ''
          { webserver =
              { path = "/nix/var/nix/profiles/webserver";
              };
            database =
              { config =
                  { config, pkgs, ... }:
                  { services.postgresql.enable = true;
                    services.postgresql.package = pkgs.postgresql_14;

                    system.stateVersion = "${lib.trivial.release}";
                  };
              };
          }
        '';
      description = ''
        A set of NixBSD system configurations to be run as FreeBSD jails.
      '';
    };
  };

  config = mkMerge [
    {
      warnings = optional (!config.boot.enableJails && config.jails != {})
        "jails.<name> is used, but boot.enableJails is false. To use jails.<name>, set boot.enableJails to true.";
    }

    (mkIf config.boot.enableJails {
      freebsd.rc.services = lib.mapAttrs (name: cfg: let conf = mkJailConf name cfg; in {
        name = "jail_${name}";
        description = "Start the ${name} jail specified in the system configuration.";
        path = [ pkgs.freebsd.jail ] ++ config.environment.systemPackages;
        rcorderSettings.REQUIRE = [ "mini_tmpfiles" "NETWORKING" ];
        rcorderSettings.KEYWORDS = [ "nojail" ];
        extraConfig = ''
          check_process() {
            jls -j "$1" jid 2>/dev/null
            result=$?
            if [[ $result = 0 ]]; then
              activatedInside="$(readlink ${stateDirectory}/${name}/run/current-system)"
              activatedOutside="${cfg.config.system.build.toplevel}" 
              if [[ $activatedInside != $activatedOutside ]]; then
                echo "Warning: jail ${name} is running activated as $activatedInside but this management script thinks it should be $activatedOutside" >&2
              fi
            fi
            return $result
          }
          wait_for_pids() {
            :
          }
        '';
        shellVariables = {
          command = "${pkgs.freebsd.jail}/bin/jail";
          procname = name;
          command_args = [ "-c" "-f" conf ];
          stop_cmd = [ "${pkgs.freebsd.jail}/bin/jail" "-r" "-f" conf "${name}" ];
        };
      }) config.jails;
      # Generate /etc/hosts entries for the containers.
      #networking.extraHosts = concatStrings (mapAttrsToList (name: cfg: optionalString (cfg.localAddress != null)
      #  ''
      #    ${head (splitString "/" cfg.localAddress)} ${name}.jail
      #  '') config.jails);

      systemd.tmpfiles.settings = lib.mapAttrs' (name: conf: lib.nameValuePair "jail_${name}" ({
        "${stateDirectory}/${name}".d = { };
        "${stateDirectory}/${name}/dev".d = { };
        "${stateDirectory}/${name}/tmp".d = { mode = "0777"; };
      } // (lib.mergeAttrsList (map (mnt: {
        "${stateDirectory}/${name}${mnt.mountPoint}"."${if mnt.isFile then "f" else "d"}" = { };
      }) (lib.attrValues conf.bindMounts))) // (lib.mergeAttrsList (map (mnt: {
        "${stateDirectory}/${name}${mnt}".d = { user = "root"; };
      }) conf.tmpfs)))) config.jails;
    })

    # Disable some features that are not useful in a jail.
    (mkIf config.boot.isJail {
      # jails don't have a kernel
      boot.kernel.enable = false;

      #console.enable = mkDefault false;

      #nix.optimise.automatic = mkDefault false; # the store is host managed
      #powerManagement.enable = mkDefault false;
      documentation.nixos.enable = mkDefault false;

      #networking.useHostResolvConf = mkDefault true;

      # Jails should be light-weight, so start sshd on demand.
      #services.openssh.startWhenNeeded = mkDefault true;

      # jails do not need to setup devices
      services.devd.enable = false;

      # Shut up warnings about not having a boot loader.
      system.build.installBootLoader = lib.mkDefault "${pkgs.coreutils}/bin/true";

      # Use the host's nix-daemon.
      environment.variables.NIX_REMOTE = "daemon";

    })
  ];
}
