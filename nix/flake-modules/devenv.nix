{ inputs, ... }:
{
  imports = [
    inputs.devenv.flakeModule
  ];

  perSystem =
    { config
    , pkgs
    , lib
    , ...
    }:
    # legacy
    let
      inherit (lib) optional optionals;

      elixir = config.teslamate.elixir;

      nodejs = pkgs.nodejs;

      postgres_port = 7000;
      mosquitto_port = 7001;
      process_compose_port = 7002;

      psql = pkgs.writeShellScriptBin "teslamate_psql" ''
        exec "${pkgs.postgresql}/bin/psql" --host "$DATABASE_HOST" --user "$DATABASE_USER" --port "$DATABASE_PORT" "$DATABASE_NAME" "$@"
      '';
      mosquitto_sub = pkgs.writeShellScriptBin "teslamate_sub" ''
        exec "${pkgs.mosquitto}/bin/mosquitto_sub" -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" "$@"
      '';

      devenv = {
        containers = lib.mkForce { }; # https://github.com/cachix/devenv/issues/760
        devenv.root =
          let
            devenvRootFileContent = builtins.readFile inputs.devenv-root.outPath;
          in
          pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;
        packages =
          with pkgs; [
            elixir
            elixir_ls
            node2nix
            nodejs
            prefetch-npm-deps
            # for dashboard scripts
            jq
            psql
            mosquitto
            mosquitto_sub
            config.treefmt.build.wrapper
          ]
          ++ builtins.attrValues config.treefmt.build.programs
          ++ optionals stdenv.isLinux [
            inotify-tools
            glibcLocales
          ]
          ++ optional stdenv.isDarwin terminal-notifier
          ++ optionals stdenv.isDarwin (
            with darwin.apple_sdk.frameworks;
            [
              CoreFoundation
              CoreServices
            ]
          );
        enterShell = ''
          export LOCALES="${config.teslamate.cldr}/priv/cldr";
          export PORT="4000"
          export ENCRYPTION_KEY="your_secure_encryption_key_here"
          export DATABASE_USER="teslamate"
          export DATABASE_PASS="your_secure_password_here"
          export DATABASE_NAME="teslamate"
          export DATABASE_HOST="127.0.0.1"
          export DATABASE_PORT="${toString postgres_port}"
          export MQTT_HOST="127.0.0.1"
          export MQTT_PORT="${toString mosquitto_port}"
          export RELEASE_COOKIE="1234567890123456789"
          export TZDATA_DIR="$PWD/tzdata"
          export MIX_REBAR3="${pkgs.rebar3}/bin/rebar3";
          mix deps.get
        '';
        enterTest = ''
          mix test
        '';
        processes.mqtt = {
          exec = "${pkgs.mosquitto}/bin/mosquitto -p ${toString mosquitto_port}";
        };
        process.managers.process-compose = {
          port = process_compose_port;
          tui.enable = true;
        };
        services.postgres = {
          enable = true;
          package = pkgs.postgresql_16; # 17 is not yet available in nixpkgs
          listen_addresses = "127.0.0.1";
          port = postgres_port;
          initialDatabases = [{ name = "teslamate"; }];
          initialScript = ''
            CREATE USER teslamate with encrypted password 'your_secure_password_here';
            GRANT ALL PRIVILEGES ON DATABASE teslamate TO teslamate;
            ALTER USER teslamate WITH SUPERUSER;
          '';
        };
      };
    in
    {
      devenv.shells.default = devenv;
    };
}
