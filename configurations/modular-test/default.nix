{ pkgs, lib, ... }:
{
  imports = [ ../base/default.nix ];

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  environment.systemPackages = with pkgs; [
    file
    freebsd.truss
    gitMinimal
    htop
    mini-tmpfiles
    tmux
    unzip
    vim
    zip
  ];

  system.services.python-http-server =
    { config, ... }:
    let
      inherit (lib) mkOption types;
      python-http-server = { config, ... }: {
        # Stolen from nixpkgs nixos/tests/modular-service-etc/python-http-server.nix
        _class = "service";

        options = {
          python-http-server = {
            package = mkOption {
              type = types.package;
              default = pkgs.python3;
              description = "Python package to use for the web server";
            };

            port = mkOption {
              type = types.port;
              default = 8000;
              description = "Port to listen on";
            };

            directory = mkOption {
              type = types.str;
              default = config.configData."webroot".path;
              defaultText = lib.literalExpression ''config.configData."webroot".path'';
              description = "Directory to serve files from";
            };
          };
        };

        config = {
          process.argv = [
            "${lib.getExe config.python-http-server.package}"
            "-m"
            "http.server"
            "${toString config.python-http-server.port}"
            "--directory"
            config.python-http-server.directory
          ];

          configData = {
            "webroot" = {
              # Enable only if directory is set to use this path
              enable = lib.mkDefault (config.python-http-server.directory == config.configData."webroot".path);
            };
          };
        };
      };
    in
    {
      _class = "service";

      imports = [ python-http-server ];

      python-http-server = {
        port = 8080;
      };

      configData = {
        "webroot" = {
          source = pkgs.runCommand "webroot" { } ''
            mkdir -p $out
            cat > $out/index.html << 'EOF'
            <!DOCTYPE html>
            <html>
            <head><title>Python Web Server</title></head>
            <body>
              <h1>Welcome to the Python Web Server</h1>
              <p>Serving from port 8080</p>
            </body>
            </html>
            EOF
          '';
        };
      };

      # Add a sub-service
      services.api = {
        imports = [ python-http-server ];
        python-http-server = {
          port = 8081;
        };
        configData = {
          "webroot" = {
            source = pkgs.runCommand "api-webroot" { } ''
              mkdir -p $out
              cat > $out/index.html << 'EOF'
              <!DOCTYPE html>
              <html>
              <head><title>API Sub-service</title></head>
              <body>
                <h1>API Sub-service</h1>
                <p>This is a sub-service running on port 8081</p>
              </body>
              </html>
              EOF
              cat > $out/status.json << 'EOF'
              {"status": "ok", "service": "api", "port": 8081}
              EOF
            '';
          };
        };
      };
    };

}
