{ config, lib, pkgs, ... }:

with lib;

{
  ###### interface

  options = {

    i18n = {
      freebsdLocales = mkOption {
        type = types.path;
        default = pkgs.freebsd.localesReal.override {
          allLocales = any (x: x == "all") config.i18n.supportedLocales;
          locales = config.i18n.supportedLocales;
        };
        defaultText = literalExpression ''
          pkgs.freebsd.locales.override {
            allLocales = any (x: x == "all") config.i18n.supportedLocales;
            locales = config.i18n.supportedLocales;
          }
        '';
        example = literalExpression "pkgs.freebsd.locales";
        description = lib.mdDoc ''
          Customized pkg.freebsd.locales package.

          Changing this option can disable handling of i18n.defaultLocale
          and supportedLocale.
        '';
      };

      defaultLocale = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
        example = "nl_NL.UTF-8";
        description = lib.mdDoc ''
          The default locale.  It determines the language for program
          messages, the format for dates and times, sort order, and so on.
          It also determines the character set, such as UTF-8.
        '';
      };

      extraLocaleSettings = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          LC_MESSAGES = "en_US.UTF-8";
          LC_TIME = "de_DE.UTF-8";
        };
        description = lib.mdDoc ''
          A set of additional system-wide locale settings other than
          `LANG` which can be configured with
          {option}`i18n.defaultLocale`.
        '';
      };

      supportedLocales = mkOption {
        type = types.listOf types.str;
        default = unique (builtins.map (l:
          (replaceStrings [ "utf8" "utf-8" "UTF8" ] [ "UTF-8" "UTF-8" "UTF-8" ]
            l) + "/UTF-8")
          ([ "C.UTF-8" "en_US.UTF-8" config.i18n.defaultLocale ] ++ (attrValues
            (filterAttrs (n: v: n != "LANGUAGE")
              config.i18n.extraLocaleSettings))));
        defaultText = literalExpression ''
          unique
            (builtins.map (l: (replaceStrings [ "utf8" "utf-8" "UTF8" ] [ "UTF-8" "UTF-8" "UTF-8" ] l) + "/UTF-8") (
              [
                "C.UTF-8"
                "en_US.UTF-8"
                config.i18n.defaultLocale
              ] ++ (attrValues (filterAttrs (n: v: n != "LANGUAGE") config.i18n.extraLocaleSettings))
            ))
        '';
        example =
          [ "en_US.UTF-8/UTF-8" "nl_NL.UTF-8/UTF-8" "nl_NL/ISO-8859-1" ];
        description = lib.mdDoc ''
          List of locales that the system should support.  The value
          `"all"` means that all locales supported by
          Glibc will be installed.  A full list of supported locales
          can be found at <https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED>.
        '';
      };

    };

  };

  ###### implementation

  config = {

    environment.systemPackages =
      optional (config.i18n.supportedLocales != [ ]) config.i18n.freebsdLocales;

    environment.pathsToLink = [ "/share/locale" ];

    environment.sessionVariables = {
      LANG = config.i18n.defaultLocale;
      PATH_LOCALE = "/run/current-system/sw/share/locale";
      MM_CHARSET = let parts = splitString "." config.i18n.defaultLocale;
      in if length parts < 2 then "UTF-8" else elemAt parts 1;
    } // config.i18n.extraLocaleSettings;
  };
}
