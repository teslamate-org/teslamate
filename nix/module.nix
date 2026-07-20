{ self }:
{ config
, lib
, pkgs
, ...
}:
let
  teslamate = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  cfg = config.services.teslamate;

  inherit (lib)
    mkPackageOption
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    getExe
    literalExpression
    ;
in
{
  options.services.teslamate = {
    enable = mkEnableOption "Teslamate";

    secretsFile = mkOption {
      type = types.str;
      example = "/run/secrets/teslamate.env";
      description = lib.mdDoc ''
        Path to an env file containing the secrets used by TeslaMate.

        The file uses systemd `EnvironmentFile` syntax (`KEY="value"` lines,
        values may be wrapped in one pair of double quotes).

        Must contain at least:
        - `ENCRYPTION_KEY` - encryption key used to encrypt database
        - `DATABASE_PASS` - password used to authenticate to database
        - `RELEASE_COOKIE` - unique value used by elixir for clustering
      '';
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to start teslamate on boot.";
    };

    listenAddress = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "127.0.0.1";
      description = "IP address where the web interface is exposed or `null` for all addresses";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port the TeslaMate service will listen on";
    };

    virtualHost = mkOption {
      type = types.str;
      default = if config.networking.domain == null then "localhost" else config.networking.fqdn;
      defaultText = literalExpression ''
        if config.networking.domain == null then "localhost" else config.networking.fqdn
      '';
      description = "Host part used for generating URLs throughout the app. Will be combined with urlPath";
    };

    urlPath = mkOption {
      type = types.str;
      default = "/";
      description = "Path prefix used for generating URLs throughout the app. Will be combined with virtualHost";
    };

    postgres = {
      enable_server = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Whether to create a postgres server with the recommended configuration.

          Other settings will still be used even if `enable` is false to configure
          database connection.
        '';
      };

      package = mkPackageOption pkgs "postgresql_17" {
        extraDescription = ''
          The postgresql package to use.
        '';
      };

      user = mkOption {
        type = types.str;
        default = "teslamate";
        description = "PostgresQL database user";
      };

      database = mkOption {
        type = types.str;
        default = "teslamate";
        description = "PostgresQL database to connect to";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Hostname of the database server";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Postgresql database port. Must be correct even if `services.teslamate.postgres.enable` is false";
      };
    };

    grafana = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to create and provision grafana with the TeslaMate dashboards";
      };

      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "IP address for grafana to listen to.";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Port for grafana web service";
      };

      urlPath = mkOption {
        type = types.str;
        default = "/";
        description = "Path that grafana is mounted on. Useful if using a reverse proxy to vend teslamate and grafana on the same port";
      };

      setDefaultDashboard = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to set the TeslaMate home dashboard as the default dashboard in Grafana";
      };

      secretKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "File with the Grafana secret_key for signing data source settings like secrets and passwords";
        default = /dev/null; # default as otherwise nix flake check fails as it is accessed with $__file
      };
    };

    mqtt = {
      enable = mkEnableOption "TeslaMate MQTT integration";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "MQTT host";
      };

      port = mkOption {
        type = with types; nullOr port;
        default = null;
        example = 1883;
        description = "MQTT port.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      users.users.teslamate = {
        isSystemUser = true;
        group = "teslamate";
        home = "/var/lib/teslamate";
        createHome = true;
      };
      users.groups.teslamate = { };

      systemd.services.teslamate = {
        description = "TeslaMate";
        after = [
          "network.target"
          "postgresql.service"
          # Database, role and password are provisioned here (no-op when using
          # an external database server, where the unit is absent).
          "postgresql-setup.service"
          "mosquitto.service"
        ];
        wantedBy = mkIf cfg.autoStart [ "multi-user.target" ];
        serviceConfig = {
          User = "teslamate";
          Restart = "on-failure";
          RestartSec = 5;

          WorkingDirectory = "/var/lib/teslamate";

          ExecStartPre = ''${getExe teslamate} eval "TeslaMate.Release.migrate"'';
          ExecStart = "${getExe teslamate} start";
          ExecStop = "${getExe teslamate} stop";

          EnvironmentFile = cfg.secretsFile;
        };
        environment = mkMerge [
          {
            PORT = toString cfg.port;
            DATABASE_USER = cfg.postgres.user;
            DATABASE_NAME = cfg.postgres.database;
            DATABASE_HOST = cfg.postgres.host;
            DATABASE_PORT = toString cfg.postgres.port;
            VIRTUAL_HOST = cfg.virtualHost;
            URL_PATH = cfg.urlPath;
            HTTP_BINDING_ADDRESS = mkIf (cfg.listenAddress != null) cfg.listenAddress;
            DISABLE_MQTT = mkIf (!cfg.mqtt.enable) "true";
          }
          # When PostgreSQL runs on the same host, connect via the local socket
          # using peer authentication instead of TCP with a password. This only
          # works for the default role name, since the socket branch in
          # runtime.exs authenticates as the systemd unit's OS user (teslamate).
          (mkIf (cfg.postgres.enable_server && cfg.postgres.user == "teslamate") {
            DATABASE_SOCKET_DIR = "/run/postgresql";
          })
          (mkIf cfg.mqtt.enable {
            MQTT_HOST = cfg.mqtt.host;
            MQTT_PORT = mkIf (cfg.mqtt.port != null) (toString cfg.mqtt.port);
          })
        ];
      };

      # idiomatic backup and restore and maintenance scripts
      environment.systemPackages = with pkgs; [
        (callPackage ./backup_and_restore.nix {
          databaseUser = cfg.postgres.user;
          databaseName = cfg.postgres.database;
        })
        (callPackage ./maintenance.nix {
          databaseUser = cfg.postgres.user;
          databaseName = cfg.postgres.database;
          environmentFilePath = cfg.secretsFile;
          getExe = getExe;
          teslamate = teslamate;
        })
      ];
    }
    (mkIf cfg.postgres.enable_server {
      services.postgresql = {
        enable = true;
        inherit (cfg.postgres) package;

        settings = {
          inherit (cfg.postgres) port;
        };

        ensureDatabases = [ cfg.postgres.database ];
        ensureUsers = [
          {
            name = cfg.postgres.user;
            ensureDBOwnership = cfg.postgres.user == cfg.postgres.database;
            # TeslaMate's migrations create the cube and earthdistance
            # extensions (see priv/repo/migrations/20190925152807_create_geo_extensions.exs).
            # These are not trusted extensions, so CREATE EXTENSION requires a
            # database superuser.
            ensureClauses.superuser = true;
          }
        ];
      };

      # ensureUsers creates the role without a password. Apply it out-of-band
      # from DATABASE_PASS so the secret never lands in the world-readable Nix
      # store (ensureUsers cannot set passwords). It is still required for
      # Grafana and for the TCP fallback (remote DB or a non-default role name),
      # even though TeslaMate itself connects via the socket with peer auth.
      #
      # ensureDatabases/ensureUsers run inside postgresql-setup.service, so we
      # hook there (after the role exists) and scope the secret to that unit.
      systemd.services.postgresql-setup = {
        serviceConfig.EnvironmentFile = cfg.secretsFile;
        # Read the password from the environment with psql's \getenv (so it is
        # never placed on the command line or shell-expanded) and quote it with
        # :'password', which produces a correctly escaped SQL string literal.
        # This is safe for any password, including ones containing single
        # quotes. Requires PostgreSQL >= 14 for \getenv.
        postStart = ''
          if [ -z "''${DATABASE_PASS:-}" ]; then
            echo "DATABASE_PASS must be set in ${cfg.secretsFile} (services.teslamate.secretsFile)" >&2
            exit 1
          fi
          psql -v ON_ERROR_STOP=1 -d postgres \
            -c '\getenv password DATABASE_PASS' \
            -c "ALTER USER \"${cfg.postgres.user}\" WITH ENCRYPTED PASSWORD :'password'"
        '';
      };
    })
    (mkIf cfg.grafana.enable {
      warnings = lib.optional (cfg.grafana.secretKeyFile == /dev/null)
        "teslamate: grafana.secretKeyFile is not set. Using the insecure default secret_key. Set grafana.secretKeyFile to a file containing a secure random key.";
      services.grafana = {
        enable = true;
        settings = {
          server = {
            domain = cfg.virtualHost;
            http_port = cfg.grafana.port;
            http_addr = cfg.grafana.listenAddress;
            root_url = "http://%(domain)s${cfg.grafana.urlPath}";
            serve_from_sub_path = cfg.grafana.urlPath != "/";
          };
          security = {
            allow_embedding = true;
            disable_gravatar = true;
            secret_key =
              if cfg.grafana.secretKeyFile == /dev/null
              then "SW2YcwTIb9zpOOhoPsMm" # old default value, see https://github.com/grafana/grafana/blob/0920e8bcc69f555a34462d0d2029a882272a0184/conf/defaults.ini#L334
              else "$__file{${cfg.grafana.secretKeyFile}}";
          };
          users = {
            allow_sign_up = false;
            default_language = "detect";
          };
          "auth.anonymous".enabled = false;
          "auth.basic".enabled = false;
          analytics.reporting_enabled = false;
          dashboards.default_home_dashboard_path = mkIf cfg.grafana.setDefaultDashboard "${pkgs.lib.sources.sourceFilesBySuffices ../grafana/dashboards/internal [".json"]}/home.json";
          date_formats.use_browser_locale = true;
          plugins.preinstall_disabled = true;
          unified_alerting.enabled = false;
        };
        provision = {
          enable = true;
          datasources.settings.datasources = [
            # extracted from ../grafana/datasource.yml
            {
              name = "TeslaMate";
              type = "postgres";
              url = "${cfg.postgres.host}:${toString cfg.postgres.port}";
              user = cfg.postgres.user;
              access = "proxy";
              basicAuth = false;
              withCredentials = false;
              isDefault = true;
              secureJsonData.password = "\${DATABASE_PASS}";
              jsonData = {
                postgresVersion = 1500;
                sslmode = "disable";
                database = cfg.postgres.database;
              };
              version = 1;
              editable = true;
            }
          ];
          # Need to duplicate dashboards.yml since it contains absolute paths
          # which are incompatible with NixOS
          dashboards.settings = {
            apiVersion = 1;
            providers = [
              {
                name = "teslamate";
                orgId = 1;
                folder = "TeslaMate";
                folderUid = "Nr4ofiDZk";
                type = "file";
                disableDeletion = false;
                allowUiUpdates = true;
                updateIntervalSeconds = 86400;
                options.path = lib.sources.sourceByRegex
                  ../grafana/dashboards
                  [ "^[^\/]*\.json$" ];
              }
              {
                name = "teslamate_internal";
                orgId = 1;
                folder = "Internal";
                folderUid = "Nr5ofiDZk";
                type = "file";
                disableDeletion = false;
                allowUiUpdates = true;
                updateIntervalSeconds = 86400;
                options.path = lib.sources.sourceFilesBySuffices
                  ../grafana/dashboards/internal
                  [ ".json" ];
              }
              {
                name = "teslamate_reports";
                orgId = 1;
                folder = "Reports";
                folderUid = "Nr6ofiDZk";
                type = "file";
                disableDeletion = false;
                allowUiUpdates = true;
                updateIntervalSeconds = 86400;
                options.path = lib.sources.sourceFilesBySuffices
                  ../grafana/dashboards/reports
                  [ ".json" ];
              }
            ];
          };
        };
      };

      systemd.services.grafana = {
        serviceConfig.EnvironmentFile = cfg.secretsFile;
        environment = {
          DATABASE_USER = cfg.postgres.user;
          DATABASE_NAME = cfg.postgres.database;
          DATABASE_HOST = cfg.postgres.host;
          DATABASE_PORT = toString cfg.postgres.port;
          DATABASE_SSL_MODE = "disable";
        };
      };
    })
  ]);
}
