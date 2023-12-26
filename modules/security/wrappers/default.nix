{ config, lib, pkgs, ... }:
let

  inherit (config.security) wrapperDir wrappers;

  parentWrapperDir = dirOf wrapperDir;

  # NixOS uses musl for this, but it doesn't make a ton of sense for freebsd, so just use fblibc
  securityWrapper = sourceProg : pkgs.callPackage ./wrapper.nix {
    inherit sourceProg;
  };

  fileModeType =
    let
      # taken from the chmod(1) man page
      symbolic = "[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+";
      numeric = "[-+=]?[0-7]{0,4}";
      mode = "((${symbolic})(,${symbolic})*)|(${numeric})";
    in
     lib.types.strMatching mode
     // { description = "file mode string"; };

  wrapperType = lib.types.submodule ({ name, config, ... }: {
    options.source = lib.mkOption
      { type = lib.types.path;
        description = lib.mdDoc "The absolute path to the program to be wrapped.";
      };
    options.program = lib.mkOption
      { type = with lib.types; nullOr str;
        default = name;
        description = lib.mdDoc ''
          The name of the wrapper program. Defaults to the attribute name.
        '';
      };
    options.owner = lib.mkOption
      { type = lib.types.str;
        description = lib.mdDoc "The owner of the wrapper program.";
      };
    options.group = lib.mkOption
      { type = lib.types.str;
        description = lib.mdDoc "The group of the wrapper program.";
      };
    options.permissions = lib.mkOption
      { type = fileModeType;
        default  = "u+rx,g+x,o+x";
        example = "a+rx";
        description = lib.mdDoc ''
          The permissions of the wrapper program. The format is that of a
          symbolic or numeric file mode understood by {command}`chmod`.
        '';
      };
    options.capabilities = lib.mkOption
      { type = lib.types.commas;
        default = "";
        description = lib.mdDoc ''
          A comma-separated list of capability clauses to be given to the
          wrapper program. The format for capability clauses is described in the
          “TEXTUAL REPRESENTATION” section of the {manpage}`cap_from_text(3)`
          manual page. For a list of capabilities supported by the system, check
          the {manpage}`capabilities(7)` manual page.

          ::: {.note}
          `cap_setpcap`, which is required for the wrapper
          program to be able to raise caps into the Ambient set is NOT raised
          to the Ambient set so that the real program cannot modify its own
          capabilities!! This may be too restrictive for cases in which the
          real program needs cap_setpcap but it at least leans on the side
          security paranoid vs. too relaxed.
          :::
        '';
      };
    options.setuid = lib.mkOption
      { type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to add the setuid bit the wrapper program.";
      };
    options.setgid = lib.mkOption
      { type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to add the setgid bit the wrapper program.";
      };
  });

  ###### Activation script for the setcap wrappers
  mkSetcapProgram =
    { program
    , capabilities
    , source
    , owner
    , group
    , permissions
    , ...
    }:
    ''
      cp ${securityWrapper source}/bin/security-wrapper "$wrapperDir/${program}"

      # Prevent races
      chmod 0000 "$wrapperDir/${program}"
      chown ${owner}:${group} "$wrapperDir/${program}"

      # Set desired capabilities on the file plus cap_setpcap so
      # the wrapper program can elevate the capabilities set on
      # its file into the Ambient set.
      ${pkgs.libcap.out}/bin/setcap "cap_setpcap,${capabilities}" "$wrapperDir/${program}"

      # Set the executable bit
      chmod ${permissions} "$wrapperDir/${program}"
    '';

  ###### Activation script for the setuid wrappers
  mkSetuidProgram =
    { program
    , source
    , owner
    , group
    , setuid
    , setgid
    , permissions
    , ...
    }:
    ''
      cp ${securityWrapper source}/bin/security-wrapper "$wrapperDir/${program}"

      # Prevent races
      chmod 0000 "$wrapperDir/${program}"
      chown ${owner}:${group} "$wrapperDir/${program}"

      chmod "u${if setuid then "+" else "-"}s,g${if setgid then "+" else "-"}s,${permissions}" "$wrapperDir/${program}"
    '';

  mkWrappedPrograms =
    builtins.map
      (opts:
        if opts.capabilities != ""
        then mkSetcapProgram opts
        else mkSetuidProgram opts
      ) (lib.attrValues wrappers);
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "security" "setuidOwners" ] "Use security.wrappers instead")
    (lib.mkRemovedOptionModule [ "security" "setuidPrograms" ] "Use security.wrappers instead")
  ];

  ###### interface

  options = {
    security.wrappers = lib.mkOption {
      type = lib.types.attrsOf wrapperType;
      default = {};
      example = lib.literalExpression
        ''
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

            # a program with the CAP_NET_RAW capability
            ping =
              { owner = "root";
                group = "root";
                capabilities = "cap_net_raw+ep";
                source = "''${pkgs.iputils.out}/bin/ping";
              };
          }
        '';
      description = lib.mdDoc ''
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
      description = lib.mdDoc ''
        Size limit for the /run/wrappers tmpfs. Look at mount(8), tmpfs size option,
        for the accepted syntax. WARNING: don't set to less than 64MB.
      '';
    };

    security.wrapperDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/run/wrappers/bin";
      internal    = true;
      description = lib.mdDoc ''
        This option defines the path to the wrapper programs. It
        should not be overridden.
      '';
    };
  };

  ###### implementation
  config = {
    # TODO
  };
}
