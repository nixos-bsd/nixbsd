# Global configuration for the SSH client.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.ssh;

  knownHosts = attrValues cfg.knownHosts;

  knownHostsText = (flip (concatMapStringsSep "\n") knownHosts (h:
    assert h.hostNames != [ ];
    optionalString h.certAuthority "@cert-authority "
    + concatStringsSep "," h.hostNames + " "
    + (if h.publicKey != null then h.publicKey else readFile h.publicKeyFile)))
    + "\n";

  knownHostsFiles = [ "/etc/ssh/ssh_known_hosts" ]
    ++ map pkgs.copyPathToStore cfg.knownHostsFiles;

in {
  ###### interface

  options = {

    programs.ssh = {
      forwardX11 = mkOption {
        type = with lib.types; nullOr bool;
        default = false;
        description = ''
          Whether to request X11 forwarding on outgoing connections by default.
          If set to null, the option is not set at all.
          This is useful for running graphical programs on the remote machine and have them display to your local X11 server.
          Historically, this value has depended on the value used by the local sshd daemon, but there really isn't a relation between the two.
          Note: there are some security risks to forwarding an X11 connection.
          NixOS's X server is built with the SECURITY extension, which prevents some obvious attacks.
          To enable or disable forwarding on a per-connection basis, see the -X and -x options to ssh.
          The -Y option to ssh enables trusted forwarding, which bypasses the SECURITY extension.
        '';
      };

      setXAuthLocation = mkOption {
        type = types.bool;
        description = ''
          Whether to set the path to {command}`xauth` for X11-forwarded connections.
          This causes a dependency on X11 packages.
        '';
      };

      pubkeyAcceptedKeyTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "ssh-ed25519" "ssh-rsa" ];
        description = ''
          Specifies the key types that will be used for public key authentication.
        '';
      };

      hostKeyAlgorithms = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "ssh-ed25519" "ssh-rsa" ];
        description = ''
          Specifies the host key algorithms that the client wants to use in order of preference.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra configuration text prepended to {file}`ssh_config`. Other generated
          options will be added after a `Host *` pattern.
          See {manpage}`ssh_config(5)`
          for help.
        '';
      };

      package = mkPackageOption pkgs "openssh" { };

      knownHosts = mkOption {
        default = { };
        type = types.attrsOf (types.submodule ({ name, config, options, ... }: {
          options = {
            certAuthority = mkOption {
              type = types.bool;
              default = false;
              description = ''
                This public key is an SSH certificate authority, rather than an
                individual host's key.
              '';
            };
            hostNames = mkOption {
              type = types.listOf types.str;
              default = [ name ] ++ config.extraHostNames;
              defaultText = literalExpression
                "[ ${name} ] ++ config.${options.extraHostNames}";
              description = ''
                A list of host names and/or IP numbers used for accessing
                the host's ssh service. This list includes the name of the
                containing `knownHosts` attribute by default
                for convenience. If you wish to configure multiple host keys
                for the same host use multiple `knownHosts`
                entries with different attribute names and the same
                `hostNames` list.
              '';
            };
            extraHostNames = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = ''
                A list of additional host names and/or IP numbers used for
                accessing the host's ssh service. This list is ignored if
                `hostNames` is set explicitly.
              '';
            };
            publicKey = mkOption {
              default = null;
              type = types.nullOr types.str;
              example = "ecdsa-sha2-nistp521 AAAAE2VjZHN...UEPg==";
              description = ''
                The public key data for the host. You can fetch a public key
                from a running SSH server with the {command}`ssh-keyscan`
                command. The public key should not include any host names, only
                the key type and the key itself.
              '';
            };
            publicKeyFile = mkOption {
              default = null;
              type = types.nullOr types.path;
              description = ''
                The path to the public key file for the host. The public
                key file is read at build time and saved in the Nix store.
                You can fetch a public key file from a running SSH server
                with the {command}`ssh-keyscan` command. The content
                of the file should follow the same format as described for
                the `publicKey` option. Only a single key
                is supported. If a host has multiple keys, use
                {option}`programs.ssh.knownHostsFiles` instead.
              '';
            };
          };
        }));
        description = ''
          The set of system-wide known SSH hosts. To make simple setups more
          convenient the name of an attribute in this set is used as a host name
          for the entry. This behaviour can be disabled by setting
          `hostNames` explicitly. You can use
          `extraHostNames` to add additional host names without
          disabling this default.
        '';
        example = literalExpression ''
          {
            myhost = {
              extraHostNames = [ "myhost.mydomain.com" "10.10.1.4" ];
              publicKeyFile = ./pubkeys/myhost_ssh_host_dsa_key.pub;
            };
            "myhost2.net".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIRuJ8p1Fi+m6WkHV0KWnRfpM1WxoW8XAS+XvsSKsTK";
            "myhost2.net/dsa" = {
              hostNames = [ "myhost2.net" ];
              publicKeyFile = ./pubkeys/myhost2_ssh_host_dsa_key.pub;
            };
          }
        '';
      };

      knownHostsFiles = mkOption {
        default = [ ];
        type = with types; listOf path;
        description = ''
          Files containing SSH host keys to set as global known hosts.
          `/etc/ssh/ssh_known_hosts` (which is
          generated by {option}`programs.ssh.knownHosts`) is
          always included.
        '';
        example = literalExpression ''
          [
            ./known_hosts
            (writeText "github.keys" '''
              github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
              github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
              github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            ''')
          ]
        '';
      };

      kexAlgorithms = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group-exchange-sha256"
        ];
        description = ''
          Specifies the available KEX (Key Exchange) algorithms.
        '';
      };

      ciphers = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ];
        description = ''
          Specifies the ciphers allowed and their order of preference.
        '';
      };

      macs = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha1" ];
        description = ''
          Specifies the MAC (message authentication code) algorithms in order of preference. The MAC algorithm is used
          for data integrity protection.
        '';
      };
    };

  };

  config = {

    # TODO(@artemist): Add other defaults from upstream ssh.nix service when reasonable
    programs.ssh.setXAuthLocation =
      mkDefault (config.programs.ssh.forwardX11 == true);

    assertions = [{
      assertion = cfg.forwardX11 == true -> cfg.setXAuthLocation;
      message = "cannot enable X11 forwarding without setting XAuth location";
    }] ++ flip mapAttrsToList cfg.knownHosts (name: data: {
      assertion = (data.publicKey == null && data.publicKeyFile != null)
        || (data.publicKey != null && data.publicKeyFile == null);
      message =
        "knownHost ${name} must contain either a publicKey or publicKeyFile";
    });

    # SSH configuration. Slight duplication of the sshd_config
    # generation in the sshd service.
    environment.etc."ssh/ssh_config".text = ''
      # Custom options from `extraConfig`, to override generated options
      ${cfg.extraConfig}

      # Generated options from other settings
      Host *
      AddressFamily any
      GlobalKnownHostsFile ${concatStringsSep " " knownHostsFiles}

      ${optionalString cfg.setXAuthLocation
      "XAuthLocation ${pkgs.xorg.xauth}/bin/xauth"}
      ${lib.optionalString (cfg.forwardX11 != null)
      "ForwardX11 ${if cfg.forwardX11 then "yes" else "no"}"}

      ${optionalString (cfg.pubkeyAcceptedKeyTypes != [ ])
      "PubkeyAcceptedKeyTypes ${
        concatStringsSep "," cfg.pubkeyAcceptedKeyTypes
      }"}
      ${optionalString (cfg.hostKeyAlgorithms != [ ])
      "HostKeyAlgorithms ${concatStringsSep "," cfg.hostKeyAlgorithms}"}
      ${optionalString (cfg.kexAlgorithms != null)
      "KexAlgorithms ${concatStringsSep "," cfg.kexAlgorithms}"}
      ${optionalString (cfg.ciphers != null)
      "Ciphers ${concatStringsSep "," cfg.ciphers}"}
      ${optionalString (cfg.macs != null)
      "MACs ${concatStringsSep "," cfg.macs}"}
    '';

    environment.etc."ssh/ssh_known_hosts".text = knownHostsText;
  };
}
