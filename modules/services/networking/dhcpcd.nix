{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.networking.dhcpcd;

  interfaces = attrValues config.networking.interfaces;

  enableDHCP = config.networking.dhcpcd.enable
    && (config.networking.useDHCP || any (i: i.useDHCP == true) interfaces);

  # Don't start dhcpcd on explicitly configured interfaces or on
  # interfaces that are part of a bridge, bond or sit device.
  ignoredInterfaces = config.networking.dhcpcd.denyInterfaces;

  arrayAppendOrNull = a1: a2:
    if a1 == null && a2 == null then
      null
    else if a1 == null then
      a2
    else if a2 == null then
      a1
    else
      a1 ++ a2;

  # If dhcp is disabled but explicit interfaces are enabled,
  # we need to provide dhcp just for those interfaces.
  allowInterfaces = arrayAppendOrNull cfg.allowInterfaces
    (if !config.networking.useDHCP && enableDHCP then
      map (i: i.name) (filter (i: i.useDHCP == true) interfaces)
    else
      null);

  staticIPv6Addresses =
    map (i: i.name) (filter (i: i.ipv6.addresses != [ ]) interfaces);

  noIPv6rs = concatStringsSep "\n" (map (name: ''
    interface ${name}
    noipv6rs
  '') staticIPv6Addresses);

  # Config file adapted from the one that ships with dhcpcd.
  dhcpcdConf = pkgs.writeText "dhcpcd.conf" ''
    # Inform the DHCP server of our hostname for DDNS.
    hostname

    # A list of options to request from the DHCP server.
    option domain_name_servers, domain_name, domain_search, host_name
    option classless_static_routes, ntp_servers, interface_mtu

    # A ServerID is required by RFC2131.
    # Commented out because of many non-compliant DHCP servers in the wild :(
    #require dhcp_server_identifier

    # A hook script is provided to lookup the hostname if not set by
    # the DHCP server, but it should not be run by default.
    nohook lookup-hostname

    denyinterfaces ${
      toString ignoredInterfaces
    } lo* peth* vif* tap* tun* virbr* vnet* vboxnet* sit*

    # Use the list of allowed interfaces if specified
    ${optionalString (allowInterfaces != null)
    "allowinterfaces ${toString allowInterfaces}"}

    # Immediately fork to background if specified, otherwise wait for IP address to be assigned
    ${{
      background = "background";
      any = "waitip";
      ipv4 = "waitip 4";
      ipv6 = "waitip 6";
      both = ''
        waitip 4
        waitip 6'';
      if-carrier-up = "";
    }.${cfg.wait}}
          
    ${optionalString (cfg.IPv6rs == null && staticIPv6Addresses != [ ])
    noIPv6rs}
    ${optionalString (cfg.IPv6rs == false) ''
      noipv6rs
    ''}

    ${cfg.extraConfig}
  '';

  exitHook = pkgs.writeText "dhcpcd.exit-hook" ''
    if [ "$reason" = BOUND -o "$reason" = REBOOT ]; then
        # Restart ntpd.  We need to restart it to make sure that it
        # will actually do something: if ntpd cannot resolve the
        # server hostnames in its config file, then it will never do
        # anything ever again ("couldn't resolve ..., giving up on
        # it"), so we silently lose time synchronisation. This also
        # applies to openntpd.
        test -x /etc/rc.d/ntpd && /etc/rc.d/ntpd restart
        test -x /etc/rc.d/chronyd && /etc/rc.d/chronyd restart
    fi

    ${cfg.runHook}
  '';

in {

  ###### interface

  options = {

    networking.dhcpcd.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable dhcpcd for device configuration. This is mainly to
        explicitly disable dhcpcd (for example when using networkd).
      '';
    };

    networking.dhcpcd.persistent = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whenever to leave interfaces configured on dhcpcd daemon
        shutdown. Set to true if you have your root or store mounted
        over the network or this machine accepts SSH connections
        through DHCP interfaces and clients should be notified when
        it shuts down.
      '';
    };

    networking.dhcpcd.denyInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Disable the DHCP client for any interface whose name matches
        any of the shell glob patterns in this list. The purpose of
        this option is to blacklist virtual interfaces such as those
        created by Xen, libvirt, LXC, etc.
      '';
    };

    networking.dhcpcd.allowInterfaces = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = ''
        Enable the DHCP client for any interface whose name matches
        any of the shell glob patterns in this list. Any interface not
        explicitly matched by this pattern will be denied. This pattern only
        applies when non-null.
      '';
    };

    networking.dhcpcd.extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Literal string to append to the config file generated for dhcpcd.
      '';
    };

    networking.dhcpcd.IPv6rs = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Force enable or disable solicitation and receipt of IPv6 Router Advertisements.
        This is required, for example, when using a static unique local IPv6 address (ULA)
        and global IPv6 address auto-configuration with SLAAC.
      '';
    };

    networking.dhcpcd.runHook = mkOption {
      type = types.lines;
      default = "";
      example =
        "if [[ $reason =~ BOUND ]]; then echo $interface: Routers are $new_routers - were $old_routers; fi";
      description = ''
        Shell code that will be run after all other hooks. See
        `man dhcpcd-run-hooks` for details on what is possible.
      '';
    };

    networking.dhcpcd.wait = mkOption {
      type =
        types.enum [ "background" "any" "ipv4" "ipv6" "both" "if-carrier-up" ];
      default = "any";
      description = ''
        This option specifies when the dhcpcd service will fork to background.
        If set to "background", dhcpcd will fork to background immediately.
        If set to "ipv4" or "ipv6", dhcpcd will wait for the corresponding IP
        address to be assigned. If set to "any", dhcpcd will wait for any type
        (IPv4 or IPv6) to be assigned. If set to "both", dhcpcd will wait for
        both an IPv4 and an IPv6 address before forking.
        The option "if-carrier-up" is equivalent to "any" if either ethernet
        is plugged nor WiFi is powered, and to "background" otherwise.
      '';
    };

  };

  ###### implementation

  config = mkIf enableDHCP {
    init.services.dhcpcd = {
      description = "DHCP Client";
      dependencies = [ "FILESYSTEMS" "network_defaults" ];
      before = [ "NETWORKING" ];

      path = [
        config.networking.resolvconf.package
        pkgs.dhcpcd
      ];

      startType = "forking";
      pidFile = "/var/run/dhcpcd/pid";
      startCommand = [ "${pkgs.dhcpcd}/sbin/dhcpcd" "--quiet" "--config" (toString dhcpcdConf) ]
        ++ optional cfg.persistent "--persistent";
    };

    systemd.tmpfiles.settings.dhcpcd."/var/run/dhcpcd".d = { user = "dhcpcd"; group = "dhcpcd"; mode = "0700"; };

    users.users.dhcpcd = {
      isSystemUser = true;
      group = "dhcpcd";
    };
    users.groups.dhcpcd = { };

    environment.systemPackages = [ pkgs.dhcpcd ];

    environment.etc."dhcpcd.exit-hook".source = exitHook;
  };

}
