{ self }:
{ config, lib, pkgs, ...}:
let
  teslamate = self.packages.${pkgs.system}.default;
  cfg = config.services.teslamate;

  inherit (lib) mkEnableOption mkOption types mkIf mkMerge getExe literalExpression;
in {
  options.services.teslamate = {
    enable = mkEnableOption "Teslamate";

    secretsFile = mkOption {
      type = types.str;
      example = "/run/secrets/teslamate.env";
      description = lib.mdDoc ''
        Path to an env file containing the secrets used by TeslaMate.

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

  config = mkIf cfg.enable 
    (mkMerge [
      {
        users.users.teslamate = {
          isSystemUser = true;
          group = "teslamate";
          home = "/var/lib/teslamate";
          createHome = true;
        };
        users.groups.teslamate = {};

        systemd.services.teslamate = {
          description = "TeslaMate";
          after = [ "network.target" "postgresql.service" ];
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
            (mkIf cfg.mqtt.enable {
              MQTT_HOST = cfg.mqtt.host;
              MQTT_PORT = mkIf (cfg.mqtt.port != null) (toString cfg.mqtt.port);
            })
          ];
        };
      }
      (mkIf cfg.postgres.enable_server {
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_16;
          inherit (cfg.postgres) port;
          
          initialScript = pkgs.writeText "teslamate-psql-init" ''
            \set password `echo $DATABASE_PASS`
            CREATE DATABASE ${cfg.postgres.database};
            CREATE USER ${cfg.postgres.user} with encrypted password :'password';
            GRANT ALL PRIVILEGES ON DATABASE ${cfg.postgres.database} TO ${cfg.postgres.user};
            ALTER USER ${cfg.postgres.user} WITH SUPERUSER;
          '';
        };
        
        # Include secrets in postgres as well
        systemd.services.postgresql = {
          serviceConfig = {
            EnvironmentFile = cfg.secretsFile;
          };
        };
      })
      (mkIf cfg.grafana.enable {
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
              disable_gravatr = true;
            };
            users = {
              allow_sign_up = false;
            };
            "auth.anonymous".enabled = false;
            "auth.basic".enabled = false;
            analytics.reporting_enabled = false;
          };
          provision = {
            enable = true;
            datasources.path = ./grafana/datasource.yml;
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
                  editable = true;
                  updateIntervalSeconds = 86400;
                  options.path = lib.sources.sourceFilesBySuffices
                    ./grafana/dashboards
                    [ ".json" ];
                }
                {
                  name = "teslamate_internal";
                  orgId = 1;
                  folder = "Internal";
                  folderUid = "Nr5ofiDZk";
                  type = "file";
                  disableDeletion = false;
                  editable = true;
                  updateIntervalSeconds = 86400;
                  options.path = lib.sources.sourceFilesBySuffices
                    ./grafana/dashboards/internal
                    [ ".json" ];
                }
                {
                  name = "teslamate_reports";
                  orgId = 1;
                  folder = "Reports";
                  folderUid = "Nr6ofiDZk";
                  type = "file";
                  disableDeletion = false;
                  editable = true;
                  updateIntervalSeconds = 86400;
                  options.path = lib.sources.sourceFilesBySuffices
                    ./grafana/dashboards/reports
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
