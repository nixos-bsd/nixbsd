{ config, lib, pkgs, ... }:
let

  inherit (config.security) wrapperDir wrappers;

  parentWrapperDir = dirOf wrapperDir;

  # NixOS uses musl for this, but it doesn't make a ton of sense for freebsd, so just use fblibc
  securityWrapper = sourceProg:
    pkgs.callPackage ./wrapper.nix { inherit sourceProg; };

  fileModeType = let
    # taken from the chmod(1) man page
    symbolic = "[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+";
    numeric = "[-+=]?[0-7]{0,4}";
    mode = "((${symbolic})(,${symbolic})*)|(${numeric})";
  in lib.types.strMatching mode // { description = "file mode string"; };

  wrapperType = lib.types.submodule ({ name, config, ... }: {
    options.source = lib.mkOption {
      type = lib.types.path;
      description = "The absolute path to the program to be wrapped.";
    };
    options.program = lib.mkOption {
      type = with lib.types; nullOr str;
      default = name;
      description = ''
        The name of the wrapper program. Defaults to the attribute name.
      '';
    };
    options.owner = lib.mkOption {
      type = lib.types.str;
      description = "The owner of the wrapper program.";
    };
    options.group = lib.mkOption {
      type = lib.types.str;
      description = "The group of the wrapper program.";
    };
    options.permissions = lib.mkOption {
      type = fileModeType;
      default = "u+rx,g+x,o+x";
      example = "a+rx";
      description = ''
        The permissions of the wrapper program. The format is that of a
        symbolic or numeric file mode understood by {command}`chmod`.
      '';
    };
    options.setuid = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Whether to add the setuid bit to the wrapper program.";
    };
    options.setgid = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Whether to add the setgid bit to the wrapper program.";
    };
  });

  ###### Activation script for the setuid wrappers
  mkSetuidProgram =
    { program, source, owner, group, setuid, setgid, permissions, ... }: ''
      cp ${securityWrapper source}/bin/security-wrapper "$wrapperDir/${program}"

      # Prevent races
      chmod 0000 "$wrapperDir/${program}"
      chown ${owner}:${group} "$wrapperDir/${program}"

      chmod "u${if setuid then "+" else "-"}s,g${
        if setgid then "+" else "-"
      }s,${permissions}" "$wrapperDir/${program}"
    '';

  mkWrappedPrograms = builtins.map mkSetuidProgram (lib.attrValues wrappers);
in {
  imports = [
    (lib.mkRemovedOptionModule [ "security" "setuidOwners" ]
      "Use security.wrappers instead")
    (lib.mkRemovedOptionModule [ "security" "setuidPrograms" ]
      "Use security.wrappers instead")
  ];

  ###### interface

  options = {
    security.wrappers = lib.mkOption {
      type = lib.types.attrsOf wrapperType;
      default = { };
      example = lib.literalExpression ''
        {
          # a setuid root program
          doas =
            { setuid = true;
              owner = "root";
              group = "root";
              source = "''${pkgs.doas}/bin/doas";
            };

          # a setgid program
          locate =
            { setgid = true;
              owner = "root";
              group = "mlocate";
              source = "''${pkgs.locate}/bin/locate";
            };
        }
      '';
      description = ''
        This option effectively allows adding setuid/setgid bits, capabilities,
        changing file ownership and permissions of a program without directly
        modifying it. This works by creating a wrapper program under the
        {option}`security.wrapperDir` directory, which is then added to
        the shell `PATH`.
      '';
    };

    security.wrapperDirSize = lib.mkOption {
      default = "50%";
      example = "10G";
      type = lib.types.str;
      description = ''
        Size limit for the /run/wrappers tmpfs. Look at mount(8), tmpfs size option,
        for the accepted syntax. WARNING: don't set to less than 64MB.
      '';
    };

    security.wrapperDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/wrappers/bin";
      internal = true;
      description = ''
        This option defines the path to the wrapper programs. It
        should not be overridden.
      '';
    };
  };

  ###### implementation
  config = {
    #security.wrappers =
    #  let
    #    mkSetuidRoot = source:
    #      { setuid = true;
    #        owner = "root";
    #        group = "root";
    #        inherit source;
    #      };
    #  in
    #  { # These are mount related wrappers that require the +s permission.
    #    fusermount  = mkSetuidRoot "${pkgs.fuse}/bin/fusermount";
    #    fusermount3 = mkSetuidRoot "${pkgs.fuse3}/bin/fusermount3";
    #    mount  = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/mount";
    #    umount = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/umount";
    #  };

    boot.specialFileSystems.${parentWrapperDir} = {
      fsType = "tmpfs";
      options = [ "mode=755" "size=${config.security.wrapperDirSize}" ];
    };

    # Make sure our wrapperDir exports to the PATH env variable when
    # initializing the shell
    environment.extraInit = ''
      # Wrappers override other bin directories.
      export PATH="${wrapperDir}:$PATH"
    '';

    init.services.suid_sgid_wrappers = {
      description = "Create SUID/SGID Wrappers";
      dependencies = [ "FILESYSTEMS" ];
      before = [ "LOGIN" ];
      startType = "oneshot";
      startCommand = [ (pkgs.writeScript "suid-sgid-wrappers-start"
      ''
        #!${pkgs.runtimeShell}
        chmod 755 "${parentWrapperDir}"

        # We want to place the tmpdirs for the wrappers to the parent dir.
        wrapperDir=$(mktemp --directory --tmpdir="${parentWrapperDir}" wrappers.XXXXXXXXXX)
        chmod a+rx "$wrapperDir"

        ${lib.concatStringsSep "\n" mkWrappedPrograms}

        if [ -L ${wrapperDir} ]; then
          # Atomically replace the symlink
          # See https://axialcorps.com/2013/07/03/atomically-replacing-files-and-directories/
          old=$(readlink -f ${wrapperDir})
          if [ -e "${wrapperDir}-tmp" ]; then
            rm --force --recursive "${wrapperDir}-tmp"
          fi
          ln --symbolic --force --no-dereference "$wrapperDir" "${wrapperDir}-tmp"
          mv --no-target-directory "${wrapperDir}-tmp" "${wrapperDir}"
          rm --force --recursive "$old"
        else
          # For initial setup
          ln --symbolic "$wrapperDir" "${wrapperDir}"
        fi
      ''
      )];
    };

    ###### wrappers consistency checks
    system.checks = lib.singleton
      (pkgs.runCommandLocal "ensure-all-wrappers-paths-exist" { } ''
        # make sure we produce output
        mkdir -p $out

        echo -n "Checking that Nix store paths of all wrapped programs exist... "

        declare -A wrappers
        ${lib.concatStringsSep "\n"
        (lib.mapAttrsToList (n: v: "wrappers['${n}']='${v.source}'") wrappers)}

        for name in "''${!wrappers[@]}"; do
          path="''${wrappers[$name]}"
          if [[ "$path" =~ /nix/store ]] && [ ! -e "$path" ]; then
            test -t 1 && echo -ne '\033[1;31m'
            echo "FAIL"
            echo "The path $path does not exist!"
            echo 'Please, check the value of `security.wrappers."'$name'".source`.'
            test -t 1 && echo -ne '\033[0m'
            exit 1
          fi
        done

        echo "OK"
      '');
  };
}
