{ config, lib, pkgs, ... }:

with lib;

let
  systemBuilder = ''
    mkdir $out

    ln -s ${config.system.build.etc}/etc $out/etc
    ln -s ${config.system.path} $out/sw
    ln -s ${config.system.init}/bin/init $out/init

    echo -n "${pkgs.stdenv.hostPlatform.system}" > $out/system

    ${config.system.systemBuilderCommands}

    cp "$extraDependenciesPath" "$out/extra-dependencies"

    ${optionalString config.boot.bootspec.enable ''
      ${config.boot.bootspec.writer}
      ${optionalString config.boot.bootspec.enableValidation ''
        ${config.boot.bootspec.validator} "$out/${config.boot.bootspec.filename}"''}
    ''}

    ${config.system.extraSystemBuilderCmds}
  '';

  # Putting it all together.  This builds a store path containing
  # symlinks to the various parts of the built configuration (the
  # kernel, systemd units, init scripts, etc.) as well as a script
  # `switch-to-configuration' that activates the configuration and
  # makes it bootable. See `activatable-system.nix`.
  baseSystem = pkgs.stdenvNoCC.mkDerivation ({
    name = "nixos-system-${config.system.name}";
    preferLocalBuild = true;
    allowSubstitutes = false;
    passAsFile = [ "extraDependencies" ];
    buildCommand = systemBuilder;

    inherit (config.system) extraDependencies;
  } // config.system.systemBuilderArgs);

  # Handle assertions and warnings

  failedAssertions =
    map (x: x.message) (filter (x: !x.assertion) config.assertions);

  baseSystemAssertWarn = if failedAssertions != [ ] then
    throw ''

      Failed assertions:
      ${concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}''
  else
    showWarnings config.warnings baseSystem;

  # Replace runtime dependencies
  system = foldr ({ oldDependency, newDependency }:
    drv:
    pkgs.replaceDependency { inherit oldDependency newDependency drv; })
    baseSystemAssertWarn config.system.replaceRuntimeDependencies;

  systemWithBuildDeps = system.overrideAttrs (o: {
    systemBuildClosure = pkgs.closureInfo { rootPaths = [ system.drvPath ]; };
    buildCommand = o.buildCommand + ''
      ln -sn $systemBuildClosure $out/build-closure
    '';
  });

in {
  options = {
    system.boot.loader.id = mkOption {
      internal = true;
      default = "";
      description = ''
        Id string of the used bootloader.
      '';
    };

    system.build = {
      toplevel = mkOption {
        type = types.package;
        readOnly = true;
        description = ''
          This option contains the store path that typically represents a NixOS system.

          You can read this path in a custom deployment tool for example.
        '';
      };
    };

    system.systemBuilderCommands = mkOption {
      type = types.lines;
      internal = true;
      default = "";
      description = ''
        This code will be added to the builder creating the system store path.
      '';
    };

    system.systemBuilderArgs = mkOption {
      type = types.attrsOf types.unspecified;
      internal = true;
      default = { };
      description = ''
        `lib.mkDerivation` attributes that will be passed to the top level system builder.
      '';
    };

    system.forbiddenDependenciesRegex = mkOption {
      default = "";
      example = "-dev$";
      type = types.str;
      description = ''
        A POSIX Extended Regular Expression that matches store paths that
        should not appear in the system closure, with the exception of {option}`system.extraDependencies`, which is not checked.
      '';
    };

    system.extraSystemBuilderCmds = mkOption {
      type = types.lines;
      internal = true;
      default = "";
      description = ''
        This code will be added to the builder creating the system store path.
      '';
    };

    system.init = mkOption {
      type = types.package;
      default = pkgs.pkgsStatic.freebsd.init;
      description = ''
        Package that contains the `init` executable. This is a binary that runs rc, not rc itself.
      '';
    };

    system.extraDependencies = mkOption {
      type = types.listOf types.pathInStore;
      default = [ ];
      description = ''
        A list of paths that should be included in the system
        closure but generally not visible to users.

        This option has also been used for build-time checks, but the
        `system.checks` option is more appropriate for that purpose as checks
        should not leave a trace in the built system configuration.
      '';
    };

    system.checks = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Packages that are added as dependencies of the system's build, usually
        for the purpose of validating some part of the configuration.

        Unlike `system.extraDependencies`, these store paths do not
        become part of the built system configuration.
      '';
    };

    system.replaceRuntimeDependencies = mkOption {
      default = [ ];
      example = lib.literalExpression
        "[ ({ original = pkgs.openssl; replacement = pkgs.callPackage /path/to/openssl { }; }) ]";
      type = types.listOf (types.submodule ({ ... }: {
        options.original = mkOption {
          type = types.package;
          description = "The original package to override.";
        };

        options.replacement = mkOption {
          type = types.package;
          description = "The replacement package.";
        };
      }));
      apply = map ({ original, replacement, ... }: {
        oldDependency = original;
        newDependency = replacement;
      });
      description = ''
        List of packages to override without doing a full rebuild.
        The original derivation and replacement derivation must have the same
        name length, and ideally should have close-to-identical directory layout.
      '';
    };

    system.name = mkOption {
      type = types.str;
      default = if config.networking.hostName == "" then
        "unnamed"
      else
        config.networking.hostName;
      defaultText = literalExpression ''
        if config.networking.hostName == ""
        then "unnamed"
        else config.networking.hostName;
      '';
      description = ''
        The name of the system used in the {option}`system.build.toplevel` derivation.

        That derivation has the following name:
        `"nixos-system-''${config.system.name}-''${config.system.nixos.label}"`
      '';
    };

    system.includeBuildDependencies = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to include the build closure of the whole system in
        its runtime closure.  This can be useful for making changes
        fully offline, as it includes all sources, patches, and
        intermediate outputs required to build all the derivations
        that the system depends on.

        Note that this includes _all_ the derivations, down from the
        included applications to their sources, the compilers used to
        build them, and even the bootstrap compiler used to compile
        the compilers. This increases the size of the system and the
        time needed to download its dependencies drastically: a
        minimal configuration with no extra services enabled grows
        from ~670MiB in size to 13.5GiB, and takes proportionally
        longer to download.
      '';
    };

  };

  config = {
    system.extraSystemBuilderCmds =
      optionalString (config.system.forbiddenDependenciesRegex != "") ''
        if [[ $forbiddenDependenciesRegex != "" && -n $closureInfo ]]; then
          if forbiddenPaths="$(grep -E -- "$forbiddenDependenciesRegex" $closureInfo/store-paths)"; then
            echo -e "System closure $out contains the following disallowed paths:\n$forbiddenPaths"
            exit 1
          fi
        fi
      '';

    system.systemBuilderArgs = {
      # Not actually used in the builder. `passedChecks` is just here to create
      # the build dependencies. Checks are similar to build dependencies in the
      # sense that if they fail, the system build fails. However, checks do not
      # produce any output of value, so they are not used by the system builder.
      # In fact, using them runs the risk of accidentally adding unneeded paths
      # to the system closure, which defeats the purpose of the `system.checks`
      # option, as opposed to `system.extraDependencies`.
      passedChecks = concatStringsSep " " config.system.checks;
    } // lib.optionalAttrs (config.system.forbiddenDependenciesRegex != "") {
      inherit (config.system) forbiddenDependenciesRegex;
      closureInfo = pkgs.closureInfo {
        rootPaths = [
          # override to avoid  infinite recursion (and to allow using extraDependencies to add forbidden dependencies)
          (config.system.build.toplevel.overrideAttrs (_: {
            extraDependencies = [ ];
            closureInfo = null;
          }))
        ];
      };
    };

    system.build.toplevel = if config.system.includeBuildDependencies then
      systemWithBuildDeps
    else
      system;

  };

}
