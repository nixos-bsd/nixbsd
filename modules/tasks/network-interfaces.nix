{ config, options, lib, pkgs, utils, ... }:

with lib;
with utils;

let

  cfg = config.networking;
  opt = options.networking;
  interfaces = attrValues cfg.interfaces;
  hasVirtuals = any (i: i.virtual) interfaces;

  addrOpts = v:
    assert v == 4 || v == 6; {
      options = {
        address = mkOption {
          type = types.str;
          description = lib.mdDoc ''
            IPv${
              toString v
            } address of the interface. Leave empty to configure the
            interface using DHCP.
          '';
        };

        prefixLength = mkOption {
          type = types.addCheck types.int
            (n: n >= 0 && n <= (if v == 4 then 32 else 128));
          description = lib.mdDoc ''
            Subnet mask of the interface, specified as the number of
            bits in the prefix (`${if v == 4 then "24" else "64"}`).
          '';
        };
      };
    };

  routeOpts = v: {
    options = {
      address = mkOption {
        type = types.str;
        description = lib.mdDoc "IPv${toString v} address of the network.";
      };

      prefixLength = mkOption {
        type = types.addCheck types.int
          (n: n >= 0 && n <= (if v == 4 then 32 else 128));
        description = lib.mdDoc ''
          Subnet mask of the network, specified as the number of
          bits in the prefix (`${if v == 4 then "24" else "64"}`).
        '';
      };

      via = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = lib.mdDoc "IPv${toString v} address of the next hop.";
      };

      flags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "xresolve" "nostatic" ];
        description = lib.mdDoc ''
          Route flags, as can be seen in {manpage}`route(8)`.
          These do not contain a value, just a flag. This is
          in contrast with modifiers, which contain a flag and a value.
        '';
      };

      modifiers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          mtu = "1492";
          ifa = if v == 4 then "192.0.2.2" else "2001:db8::acab";
        };
        description = lib.mdDoc ''
          Route modifiers that may be changed by the kernel automatically.
          Most are listed in {manpage}`route(8)`, though some, like `weight`
          are undocumented.
        '';
      };

      lockedModifiers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { mtu = "1492"; };
        description = lib.mdDoc ''
          Route modifiers that may not be changed by the kernel automatically.
          Most are listed in {manpage}`route(8)`, though some, like `weight`
          are undocumented.
        '';
      };
    };
  };

  gatewayCoerce = address: { inherit address; };

  gatewayOpts = { ... }: {

    options = {

      address = mkOption {
        type = types.str;
        description = lib.mdDoc "The default gateway address.";
      };

      interface = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "enp0s3";
        description = lib.mdDoc "The default gateway interface.";
      };

      metric = mkOption {
        type = types.nullOr types.int;
        default = null;
        example = 42;
        description = lib.mdDoc "The default gateway metric/preference.";
      };

    };

  };

  interfaceOpts = { name, ... }: {

    options = {
      name = mkOption {
        example = "eth0";
        type = types.str;
        description = lib.mdDoc "Name of the interface.";
      };

      useDHCP = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = lib.mdDoc ''
          Whether this interface should be configured with DHCP. Overrides the
          default set by {option}`networking.useDHCP`. If `null` (the default),
          DHCP is enabled if the interface has no IPv4 addresses configured
          with {option}`networking.interfaces.<name>.ipv4.addresses`, and
          disabled otherwise.
        '';
      };

      ipv4.addresses = mkOption {
        default = [ ];
        example = [
          {
            address = "10.0.0.1";
            prefixLength = 16;
          }
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];
        type = with types; listOf (submodule (addrOpts 4));
        description = lib.mdDoc ''
          List of IPv4 addresses that will be statically assigned to the interface.
        '';
      };

      ipv6.addresses = mkOption {
        default = [ ];
        example = [
          {
            address = "fdfd:b3f0:482::1";
            prefixLength = 48;
          }
          {
            address = "2001:1470:fffd:2098::e006";
            prefixLength = 64;
          }
        ];
        type = with types; listOf (submodule (addrOpts 6));
        description = lib.mdDoc ''
          List of IPv6 addresses that will be statically assigned to the interface.
        '';
      };

      ipv4.routes = mkOption {
        default = [ ];
        example = [
          {
            address = "10.0.0.0";
            prefixLength = 16;
          }
          {
            address = "192.168.2.0";
            prefixLength = 24;
            via = "192.168.1.1";
          }
        ];
        type = with types; listOf (submodule (routeOpts 4));
        description = lib.mdDoc ''
          List of extra IPv4 static routes that will be assigned to the interface.

          ::: {.warning}
          If the route type is the default `unicast`, then the scope
          is set differently depending on the value of {option}`networking.useNetworkd`:
          the script-based backend sets it to `link`, while networkd sets
          it to `global`.
          :::

          If you want consistency between the two implementations,
          set the scope of the route manually with
          `networking.interfaces.eth0.ipv4.routes = [{ options.scope = "global"; }]`
          for example.
        '';
      };

      ipv6.routes = mkOption {
        default = [ ];
        example = [
          {
            address = "fdfd:b3f0::";
            prefixLength = 48;
          }
          {
            address = "2001:1470:fffd:2098::";
            prefixLength = 64;
            via = "fdfd:b3f0::1";
          }
        ];
        type = with types; listOf (submodule (routeOpts 6));
        description = lib.mdDoc ''
          List of extra IPv6 static routes that will be assigned to the interface.
        '';
      };

      macAddress = mkOption {
        default = null;
        example = "00:11:22:33:44:55";
        type = types.nullOr (types.str);
        description = lib.mdDoc ''
          MAC address of the interface. Leave empty to use the default.
        '';
      };

      mtu = mkOption {
        default = null;
        example = 9000;
        type = types.nullOr types.int;
        description = lib.mdDoc ''
          MTU size for packets leaving the interface. Leave empty to use the default.
        '';
      };

      virtual = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc ''
          Whether this interface is virtual and should be created by tunctl.
          This is mainly useful for creating bridges between a host and a virtual
          network such as VPN or a virtual machine.
        '';
      };

      virtualOwner = mkOption {
        default = "root";
        type = types.str;
        description = lib.mdDoc ''
          In case of a virtual device, the user who owns it.
        '';
      };

      virtualType = mkOption {
        default = if hasPrefix "tun" name then "tun" else "tap";
        defaultText =
          literalExpression ''if hasPrefix "tun" name then "tun" else "tap"'';
        type = with types; enum [ "tun" "tap" ];
        description = lib.mdDoc ''
          The type of interface to create.
          The default is TUN for an interface name starting
          with "tun", otherwise TAP.
        '';
      };
    };

    config = { name = mkDefault name; };
  };

  hexChars = stringToCharacters "0123456789abcdef";

  isHexString = s: all (c: elem c hexChars) (stringToCharacters (toLower s));

  tempaddrValues = {
    disabled = {
      use_tempaddr = "0";
      prefer_tempaddr = "0";
      description = "completely disable IPv6 temporary addresses";
    };
    enabled = {
      use_tempaddr = "1";
      prefer_tempaddr = "0";
      description =
        "generate IPv6 temporary addresses but still use EUI-64 addresses as source addresses";
    };
    default = {
      use_tempaddr = "1";
      prefer_tempaddr = "1";
      description =
        "generate IPv6 temporary addresses and use these as source addresses in routing";
    };
  };
  tempaddrDoc = concatStringsSep "\n" (mapAttrsToList
    (name: { description, ... }: ''- `"${name}"` to ${description};'')
    tempaddrValues);

  hostidFile = pkgs.runCommand "gen-hostid" { preferLocalBuild = true; } ''
    hi="${cfg.hostId}"
    ${if pkgs.stdenv.isBigEndian then ''
      echo -ne "\x''${hi:0:2}\x''${hi:2:2}\x''${hi:4:2}\x''${hi:6:2}" > $out
    '' else ''
      echo -ne "\x''${hi:6:2}\x''${hi:4:2}\x''${hi:2:2}\x''${hi:0:2}" > $out
    ''}
  '';

in {

  ###### interface

  options = {

    networking.hostName = mkOption {
      default = config.system.nixos.distroId;
      defaultText = literalExpression "config.system.nixos.distroId";
      # Only allow hostnames without the domain name part (i.e. no FQDNs, see
      # e.g. "man 5 hostname") and require valid DNS labels (recommended
      # syntax). Note: We also allow underscores for compatibility/legacy
      # reasons (as undocumented feature):
      type =
        types.strMatching "^$|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$";
      description = lib.mdDoc ''
        The name of the machine. Leave it empty if you want to obtain it from a
        DHCP server (if using DHCP). The hostname must be a valid DNS label (see
        RFC 1035 section 2.3.1: "Preferred name syntax", RFC 1123 section 2.1:
        "Host Names and Numbers") and as such must not contain the domain part.
        This means that the hostname must start with a letter or digit,
        end with a letter or digit, and have as interior characters only
        letters, digits, and hyphen. The maximum length is 63 characters.
        Additionally it is recommended to only use lower-case characters.
        If (e.g. for legacy reasons) a FQDN is required as the Linux kernel
        network node hostname (uname --nodename) the option
        boot.kernel.sysctl."kernel.hostname" can be used as a workaround (but
        the 64 character limit still applies).

        WARNING: Do not use underscores (_) or you may run into unexpected issues.
      '';
      # warning until the issues in https://github.com/NixOS/nixpkgs/pull/138978
      # are resolved
    };

    networking.fqdn = mkOption {
      readOnly = true;
      type = types.str;
      default = if (cfg.hostName != "" && cfg.domain != null) then
        "${cfg.hostName}.${cfg.domain}"
      else
        throw ''
          The FQDN is required but cannot be determined. Please make sure that
          both networking.hostName and networking.domain are set properly.
        '';
      defaultText =
        literalExpression ''"''${networking.hostName}.''${networking.domain}"'';
      description = lib.mdDoc ''
        The fully qualified domain name (FQDN) of this host. It is the result
        of combining `networking.hostName` and `networking.domain.` Using this
        option will result in an evaluation error if the hostname is empty or
        no domain is specified.

        Modules that accept a mere `networking.hostName` but prefer a fully qualified
        domain name may use `networking.fqdnOrHostName` instead.
      '';
    };

    networking.fqdnOrHostName = mkOption {
      readOnly = true;
      type = types.str;
      default = if cfg.domain == null then cfg.hostName else cfg.fqdn;
      defaultText = literalExpression ''
        if cfg.domain == null then cfg.hostName else cfg.fqdn
      '';
      description = lib.mdDoc ''
        Either the fully qualified domain name (FQDN), or just the host name if
        it does not exists.

        This is a convenience option for modules to read instead of `fqdn` when
        a mere `hostName` is also an acceptable value; this option does not
        throw an error when `domain` is unset.
      '';
    };

    networking.hostId = mkOption {
      default = null;
      example = "4e98920d";
      type = types.nullOr types.str;
      description = lib.mdDoc ''
        The 32-bit host ID of the machine, formatted as 8 hexadecimal characters.

        You should try to make this ID unique among your machines. You can
        generate a random 32-bit ID using the following commands:

        `head -c 8 /etc/machine-id`

        (this derives it from the machine-id that systemd generates) or

        `head -c4 /dev/urandom | od -A none -t x4`

        The primary use case is to ensure when using ZFS that a pool isn't imported
        accidentally on a wrong machine.
      '';
    };

    networking.defaultGateway = mkOption {
      default = null;
      example = {
        address = "131.211.84.1";
        interface = "enp3s0";
      };
      type = types.nullOr
        (types.coercedTo types.str gatewayCoerce (types.submodule gatewayOpts));
      description = lib.mdDoc ''
        The default gateway. It can be left empty if it is auto-detected through DHCP.
        It can be specified as a string or an option set along with a network interface.
      '';
    };

    networking.defaultGateway6 = mkOption {
      default = null;
      example = {
        address = "2001:4d0:1e04:895::1";
        interface = "enp3s0";
      };
      type = types.nullOr
        (types.coercedTo types.str gatewayCoerce (types.submodule gatewayOpts));
      description = lib.mdDoc ''
        The default ipv6 gateway. It can be left empty if it is auto-detected through DHCP.
        It can be specified as a string or an option set along with a network interface.
      '';
    };

    networking.defaultGatewayWindowSize = mkOption {
      default = null;
      example = 524288;
      type = types.nullOr types.int;
      description = lib.mdDoc ''
        The window size of the default gateway. It limits maximal data bursts that TCP peers
        are allowed to send to us.
      '';
    };

    networking.nameservers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "130.161.158.4" "130.161.33.17" ];
      description = lib.mdDoc ''
        The list of nameservers.  It can be left empty if it is auto-detected through DHCP.
      '';
    };

    networking.search = mkOption {
      default = [ ];
      example = [ "example.com" "home.arpa" ];
      type = types.listOf types.str;
      description = lib.mdDoc ''
        The list of search paths used when resolving domain names.
      '';
    };

    networking.domain = mkOption {
      default = null;
      example = "home.arpa";
      type = types.nullOr types.str;
      description = lib.mdDoc ''
        The domain.  It can be left empty if it is auto-detected through DHCP.
      '';
    };

    networking.localCommands = mkOption {
      type = types.lines;
      default = "";
      example = "text=anything; echo You can put $text here.";
      description = lib.mdDoc ''
        Shell commands to be executed at the end of the
        `network-setup` systemd service.  Note that if
        you are using DHCP to obtain the network configuration,
        interfaces may not be fully configured yet.
      '';
    };

    networking.interfaces = mkOption {
      default = { };
      example = {
        eth0.ipv4.addresses = [{
          address = "131.211.84.78";
          prefixLength = 25;
        }];
      };
      description = lib.mdDoc ''
        The configuration for each network interface.

        Please note that {option}`systemd.network.netdevs` has more features
        and is better maintained. When building new things, it is advised to
        use that instead.
      '';
      type = with types; attrsOf (submodule interfaceOpts);
    };

    networking.useDHCP = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether to use DHCP to obtain an IP address and other
        configuration for all network interfaces that do not have any manually
        configured IPv4 addresses.
      '';
    };

    networking.tempAddresses = mkOption {
      default = "default";
      type = types.enum (lib.attrNames tempaddrValues);
      description = lib.mdDoc ''
        Whether to enable IPv6 Privacy Extensions for all interfaces
        Possible values are:

        ${tempaddrDoc}
      '';
    };

  };

  ###### implementation

  config = {
    assertions = (forEach interfaces (i: {
      assertion = (i.virtual && i.virtualType == "tun") -> i.macAddress == null;
      message = ''
        Setting a MAC Address for tun device ${i.name} isn't supported.
      '';
    })) ++ [{
      assertion = cfg.hostId == null
        || (stringLength cfg.hostId == 8 && isHexString cfg.hostId);
      message = "Invalid value given to the networking.hostId option.";
    }];

    # loopback isn't setup or given an IPv4 address by default.
    # Interface is given an IPv6 address once marked up
    networking.interfaces.lo0 = {
      ipv4.addresses = [{
        address = "127.0.0.1";
        prefixLength = 8;
      }];
    };

    # Hostname/hostid stuff
    environment.etc.hostid = mkIf (cfg.hostId != null) { source = hostidFile; };
    environment.etc.hostname =
      mkIf (cfg.hostName != "") { text = cfg.hostName + "\n"; };
    rc.services = let
      hostname = {
        provides = "hostname";
        before = [ "NETWORKING" ];
        # No need to handle no hostname, it can't be null
        # TODO(@artemist): Handle set_hostname_allowed = 0 in jail
        commands.start = ''
          hostname ${escapeShellArg cfg.fqdnOrHostName}
        '';
      };

      networkDefaults = let
        formatDefaultGateway = proto: default:
          let
            parts = [ "route" "-${proto}" "-n" "add" "default" default.address ]
              ++ optionals (default.interface != null) [
                "-ifp"
                default.interface
              ] ++ optionals (default.metric != null) [
                "-weight"
                (toString default.metric)
              ];
          in ''
            route -${proto} -n -q delete default
            ${concatStringsSep " " parts}
          '';
      in {
        description = "Setup defualt routes and DNS settings";
        provides = "network_defaults";
        before = [ "NETWORKING" ];
        keywordNojailvnet = true;
        binDeps = with pkgs; [ freebsd.route freebsd.bin coreutils ];
        commands.start = ''
          ${optionalString config.networking.resolvconf.enable ''
            # Set the static DNS configuration, if given.
            ${config.networking.resolvconf.package}/sbin/resolvconf -m 1 -a static <<EOF
            ${optionalString (cfg.nameservers != [ ] && cfg.domain != null) ''
              domain ${cfg.domain}
            ''}
            ${optionalString (cfg.search != [ ])
            ("search " + concatStringsSep " " cfg.search)}
            ${flip concatMapStrings cfg.nameservers (ns: ''
              nameserver ${ns}
            '')}
            EOF
          ''}

          # Set the default gateway.
          ${optionalString
          (cfg.defaultGateway != null && cfg.defaultGateway.address != "")
          (formatDefaultGateway "4" cfg.defaultGateway)}
          ${optionalString
          (cfg.defaultGateway6 != null && cfg.defaultGateway6.address != "")
          (formatDefaultGateway "6" cfg.defaultGateway6)}
        '';
      };

      deviceDependency = dev:
        if (dev == null || dev == "lo0") then
          [ ]
        else if (count (i: i.name == dev && i.virtual) interfaces > 0) then
          [
            "netdev_${dev}"
          ]
          # TODO: figure out devd here
        else
          [ ];

      configureAddrs = i:
        let
          serviceName = "network_addresses_${i.name}";
          ips = i.ipv4.addresses ++ i.ipv6.addresses;
        in nameValuePair serviceName {
          description = "Address and route configuration of ${i.name}";
          provides = serviceName;
          before = [ "network_defaults" "NETWORKING" ];
          requires = [ "FILESYSTEMS" "tempfiles" ] ++ deviceDependency i.name;
          binDeps = with pkgs; [
            freebsd.route
            freebsd.ifconfig
            freebsd.bin
            coreutils
          ];
          commands.start = ''
            startmsg -n "Setting addresses for ${i.name}"

            state="/run/nixos/network/addresses/${i.name}"
            mkdir -p $(dirname "$state")

            ifconfig "${i.name}" up

            ${flip concatMapStrings ips (ip:
              let cidr = "${ip.address}/${toString ip.prefixLength}";
              in ''
                echo "${cidr}" >> $state
                echo -n "adding address ${cidr}... "
                if out=$(ifconfig "${i.name}" "${cidr}" alias 2>&1); then
                  echo "done"
                else
                  echo "'ifconfig "${i.name}""${cidr}" alias' failed: $out"
                  exit 1
                fi
              '')}

            ${flip concatMapStrings (i.ipv4.routes ++ i.ipv6.routes) (route:
              let
                cidr = escapeShellArg
                  "${route.address}/${toString route.prefixLength}";
                gateway = escapeShellArg
                  (if route.via == null then i.name else route.via);
                flags = map (f: "-${f}")
                  (optional (route.via == null) "iface" ++ route.flags);
                modifiers = concatLists (mapAttrsToList (k: v: [ "-${k}" v ])
                  ({ ifp = i.name; } // route.modifiers));
                lockedModifiers = concatLists
                  (mapAttrsToList (k: v: [ "-${k}" v ]) route.lockedModifiers);
                options = escapeShellArgs (flags ++ modifiers
                  ++ optional (lockedModifiers != [ ]) "-lockrest"
                  ++ lockedModifiers);
              in ''
                echo "${cidr}" >> $state
                echo -n "adding route ${cidr}... "
                if out=$(route add ${options} ${cidr} ${gateway} 2>&1); then
                  echo "done"
                elif ! echo "$out" | grep "File exists" >/dev/null 2>&1; then
                  echo "'route add ${options} ${cidr} ${gateway}' failed: $out"
                  exit 1
                fi
              '')}
          '';
        };
    in {
      inherit hostname;
      network_defaults = networkDefaults;
    } // listToAttrs (map configureAddrs interfaces);

    boot.kernel.sysctl = {
      "net.inet6.ip6.use_tempaddr" =
        tempaddrValues.${cfg.tempAddresses}.use_tempaddr;
      "net.inet6.ip6.prefer_tempaddr" =
        tempaddrValues.${cfg.tempAddresses}.prefer_tempaddr;
    };
  };
}
