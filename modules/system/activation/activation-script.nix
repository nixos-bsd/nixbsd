# generate the script used to activate the configuration.
{ config, lib, pkgs, ... }:

with lib;

let
  fsckY = if config.system.boot.autoFsck then "-y" else "";
  tosyslog = (pkgs.runCommandCC "tosyslog" {} ''
    mkdir -p $out/bin
    $CC -x c - -o $out/bin/tosyslog <<EOF
    #include <stdio.h>
    #include <syslog.h>

    int main(int argc, char **argv) {
        openlog(argc < 2 ? "init" : argv[1], LOG_CONS|LOG_ODELAY, LOG_AUTH);
        char buffer[1024];
        while (fgets(buffer, sizeof(buffer), stdin)) {
            syslog(LOG_ALERT, "%s", buffer);
        }
        return 0;
    }
    EOF
  '');

  addAttributeName = mapAttrs (a: v:
    v // {
      text = ''
        #### Activation script snippet ${a}:
        _localstatus=0
        ${v.text}

        if (( _localstatus != 0 )); then
          printf "Activation script snippet '%s' failed (%s)\n" "${a}" "$_localstatus"
        fi
      '';
    });

  systemActivationScript = set: onlyDry:
    let
      set' = mapAttrs (_: v:
        if isString v then
          (noDepEntry v) // { supportsDryActivation = false; }
        else
          v) set;
      withHeadlines = addAttributeName set';
      # When building a dry activation script, this replaces all activation scripts
      # that do not support dry mode with a comment that does nothing. Filtering these
      # activation scripts out so they don't get generated into the dry activation script
      # does not work because when an activation script that supports dry mode depends on
      # an activation script that does not, the dependency cannot be resolved and the eval
      # fails.
      withDrySnippets = mapAttrs (a: v:
        if onlyDry && !v.supportsDryActivation then
          v // {
            text =
              "#### Activation script snippet ${a} does not support dry activation.";
          }
        else
          v) withHeadlines;
    in ''
      #!${pkgs.runtimeShell}

      systemConfig='@out@'

      export PATH=/empty
      for i in ${toString path}; do
          PATH=$PATH:$i/bin:$i/sbin
      done

      if [[ $$ == 1 || $PPID == 1 ]]; then
        REALINIT=1
      fi

      '' + optionalString pkgs.stdenv.hostPlatform.isOpenBSD ''
        if [[ $REALINIT == 1 ]]; then
          exec <>/dev/console 1>&0 2>&0
        fi
      '' +
      ''

      _status=0
      _localstatus=0
      trap "_status=1 _localstatus=\$?" ERR

      # Ensure a consistent umask.
      umask 0022

      '' + optionalString (!config.boot.isJail) (''
      # Early mounts
      specialMount() {
        SRC="$1"
        DST="$2"
        OPT="$3"
        TYP="$4"
        test "$TYP" = tmpfs && SRC=tmpfs && NOFSCK=1
        test "$TYP" = devfs && SRC=devfs && NOFSCK=1
        test "$TYP" = zfs && NOFSCK=1
        mount | grep "$SRC on $DST" &>/dev/null && return 0

        mkdir -m 0755 -p "$DST"
        if [[ -z "$NOFSCK" ]]; then
          fsck -C ${fsckY} "$SRC"
        fi
        mount -o "$OPT" -t "$TYP" "$SRC" "$DST"
      }
      if [[ $REALINIT == 1 ]]; then
      '' + lib.optionalString pkgs.stdenv.hostPlatform.isOpenBSD ''
        # TODO: Support other root paths
        fsck -C ${fsckY} /dev/sd0a
        mount -u -w /dev/sd0a /
      '' + lib.optionalString pkgs.stdenv.hostPlatform.isFreeBSD ''
        ${lib.optionalString (config.fileSystems."/".fsType != "zfs" && config.fileSystems."/".fsType != "tmpfs") "fsck -C ${fsckY} /"}
        mount -u -w /
      '' + ''
        source ${config.system.build.earlyMountScript}
      fi

      if (( _localstatus != 0 )); then
        printf "Early mounts failed (%s)\n" "$_localstatus"
      fi
      _localstatus=0

      ${config.boot.postMountCommands}
      if (( _localstatus != 0 )); then
        printf "Post-mount commands failed (%s)\n" "$_localstatus"
      fi
      _localstatus=0
      '') + ''

      mkdir -p /etc /dev /var /run /nix /tmp
      chmod 777 /tmp

      ${textClosureMap id (withDrySnippets) (attrNames withDrySnippets)}

    '' + optionalString (!onlyDry) ''
      # Make this configuration the current configuration.
      # The readlink is there to ensure that when $systemConfig = /system
      # (which is a symlink to the store), /run/current-system is still
      # used as a garbage collection root.
      ln -sfn "$(readlink -f "$systemConfig")" /run/current-system

      # Likewise, the first system will be the booted-system
      [ -e /run/booted-system ] || ln -sfn "$(readlink -f "$systemConfig")" /run/booted-system

      if [[ $_status != 0 ]]; then
        echo "NixBSD system activation FAILED. Dropping into rescue shell."
        bash -i
        exit $_status
      fi
    '';

  path = with pkgs;
    map getBin ([
      coreutils
      findutils
      getent
      gnugrep
    ] ++ {
      freebsd = [
        freebsd.mount
        freebsd.fsck
        freebsd.fsck_ffs
        freebsd.fsck_msdosfs
        freebsd.nscd
        freebsd.pwd_mkdb
      ];
      openbsd = [
        openbsd.mount
        openbsd.mount_ffs
        openbsd.mount_tmpfs
        openbsd.pwd_mkdb
        openbsd.fsck
        openbsd.fsck_ffs
        openbsd.fsck_msdos
        bash
        tosyslog
      ];
    }.${pkgs.stdenv.hostPlatform.parsed.kernel.name});

  scriptType = withDry:
    with types;
    let
      scriptOptions = {
        deps = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description =
            "List of dependencies. The script will run after these.";
        };
        text = mkOption {
          type = types.lines;
          description = "The content of the script.";
        };
      } // optionalAttrs withDry {
        supportsDryActivation = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether this activation script supports being dry-activated.
            These activation scripts will also be executed on dry-activate
            activations with the environment variable
            `NIXOS_ACTION` being set to `dry-activate`.
            it's important that these activation scripts  don't
            modify anything about the system when the variable is set.
          '';
        };
      };
    in either str (submodule { options = scriptOptions; });

in {
  options = {

    system.activationScripts = mkOption {
      default = { };

      example = literalExpression ''
        { stdio.text =
          '''
            # Needed by some programs.
            ln -sfn /proc/self/fd /dev/fd
            ln -sfn /proc/self/fd/0 /dev/stdin
            ln -sfn /proc/self/fd/1 /dev/stdout
            ln -sfn /proc/self/fd/2 /dev/stderr
          ''';
        }
      '';

      description = ''
        A set of shell script fragments that are executed when a NixOS
        system configuration is activated.  Examples are updating
        /etc, creating accounts, and so on.  Since these are executed
        every time you boot the system or run
        {command}`nixos-rebuild`, it's important that they are
        idempotent and fast.
      '';

      type = types.attrsOf (scriptType true);
      apply = set: set // { script = systemActivationScript set false; };
    };

    system.dryActivationScript = mkOption {
      description = 
        "The shell script that is to be run when dry-activating a system.";
      readOnly = true;
      internal = true;
      default = systemActivationScript
        (removeAttrs config.system.activationScripts [ "script" ]) true;
      defaultText = literalMD "generated activation script";
    };

    environment.usrbinenv = mkOption {
      default = "${pkgs.coreutils}/bin/env";
      defaultText = literalExpression ''"''${pkgs.coreutils}/bin/env"'';
      example = literalExpression ''"''${pkgs.busybox}/bin/env"'';
      type = types.nullOr types.path;
      visible = false;
      description = ''
        The env(1) executable that is linked system-wide to
        `/usr/bin/env`.
      '';
    };

    system.build.installBootLoader = mkOption {
      internal = true;
      # "; true" => make the `$out` argument from switch-to-configuration.pl
      #             go to `true` instead of `echo`, hiding the useless path
      #             from the log.
      default =
        "echo 'Warning: do not know how to make this configuration bootable; please enable a boot loader.' 1>&2; true";
      description = ''
        A program that writes a bootloader installation script to the path passed in the first command line argument.

        See `nixos/modules/system/activation/switch-to-configuration.pl`.
      '';
      type = types.unique {
        message = ''
          Only one bootloader can be enabled at a time. This requirement has not
          been checked until NixOS 22.05. Earlier versions defaulted to the last
          definition. Change your configuration to enable only one bootloader.
        '';
      } (types.either types.str types.package);
    };

    boot.postMountCommands = mkOption {
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed immediately after the stage 1
        filesystems have been mounted.
      '';
    };
  };

  config = {
    system.activationScripts.stdio = ""; # obsolete
    system.activationScripts.var = ""; # obsolete

    system.activationScripts.usrbinenv =
      if config.environment.usrbinenv != null then ''
        mkdir -p /usr/bin
        chmod 0755 /usr/bin
        ln -sfn ${config.environment.usrbinenv} /usr/bin/.env.tmp
        mv /usr/bin/.env.tmp /usr/bin/env # atomically replace /usr/bin/env
      '' else ''
        rm -f /usr/bin/env
        rmdir --ignore-fail-on-non-empty /usr/bin /usr
      '';

    #systemd.tmpfiles.rules = [
    #  #"d /nix/var/nix/gcroots -"
    #  "L+ /nix/var/nix/gcroots/current-system - - - - /run/current-system"
    #  #"D /var/empty 0555 root root -"
    #  #"h /var/empty - - - - +i"
    #];
  };
}
