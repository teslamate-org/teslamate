{
  description = "TeslaMate Logger";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv/fed89fff44ccbc73f91d69ca326ac241baeb1726"; # https://github.com/cachix/devenv/issues/1497
    devenv-root.url = "file+file:///dev/null";
    devenv-root.flake = false;
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    inputs@{ self
    , flake-parts
    , devenv
    , devenv-root
    , ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      flake.nixosModules.default = import ./nix/module.nix { inherit self; };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      # See ./nix/flake-modules/*.nix for the modules that are imported here.
      imports = [
        inputs.devenv.flakeModule
        ./nix/flake-modules/checks.nix
        ./nix/flake-modules/formatter.nix
        ./nix/flake-modules/package.nix
      ];

      perSystem =
        { config
        , self'
        , inputs'
        , pkgs
        , system
        , ...
        }:
        # legacy
        let
          inherit (pkgs.lib) optional optionals;
          nixpkgs = inputs.nixpkgs;
          pkgs = nixpkgs.legacyPackages.${system};

          elixir = pkgs.beam.packages.erlang_26.elixir_1_16;

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

          devShell = inputs.devenv.lib.mkShell {
            inherit inputs pkgs;

            modules = with pkgs; [
              {
                devenv.root =
                  let
                    devenvRootFileContent = builtins.readFile devenv-root.outPath;
                  in
                  pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;
                packages =
                  [
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
                  # ++ optional stdenv.isLinux [
                  #   inotify-tools # disabled to avoid error: A definition for option `packages."[definition 4-entry 16]"' is not of type `package'.
                  #   glibcLocales # disabled to avoid error:  A definition for option `packages."[definition 4-entry 16]"' is not of type `package'.
                  # ]
                  ++ optional stdenv.isDarwin terminal-notifier
                  ++ optionals stdenv.isDarwin (
                    with darwin.apple_sdk.frameworks;
                    [
                      CoreFoundation
                      CoreServices
                    ]
                  );
                enterShell = ''
                  export LOCALES="${self'.packages.cldr}/priv/cldr";
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
                  export MIX_REBAR3="${rebar3}/bin/rebar3";
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
              }
            ];

          };
        in
        {
          packages = {
            devenv-up = devShell.config.procfileScript;
          };
          devShells.default = devShell;
        };
    };
}
