{ self, inputs, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    let
      inherit (inputs) nixpkgs;
      fakeTeslaMate = pkgs.writeShellApplication {
        name = "teslamate";
        text = ''
          case "$*" in
            *"(404)"*) printf '%s\n' ':not_found' ;;
            *"(500)"*) printf '%s\n' '{:error, :failed}' ;;
            *) printf '%s\n' ':ok' ;;
          esac
        '';
      };
      maintenance = pkgs.callPackage ../maintenance.nix {
        environmentFilePath = pkgs.writeText "teslamate.env" "RELEASE_COOKIE=test\n";
        getExe = lib.getExe;
        teslamate = fakeTeslaMate;
      };
      maintenanceScriptsTest = pkgs.runCommand "maintenance-scripts-test" { } ''
        ${maintenance}/bin/teslamate-delete-drive 1 | grep -F "Successfully deleted drive with ID 1."
        ${maintenance}/bin/teslamate-delete-drive 404 2> drive-missing.log
        grep -F "Warning: Drive with ID 404 does not exist. Nothing to delete." drive-missing.log

        ${maintenance}/bin/teslamate-delete-charge 1 | grep -F "Successfully deleted charging process with ID 1."
        ${maintenance}/bin/teslamate-delete-charge 404 2> charge-missing.log
        grep -F "Warning: Charging process with ID 404 does not exist. Nothing to delete." charge-missing.log

        if ${maintenance}/bin/teslamate-delete-drive 500 2> drive-error.log; then
          echo "delete drive unexpectedly succeeded" >&2
          exit 1
        fi
        grep -F "Error: Failed to delete drive with ID 500." drive-error.log

        touch $out
      '';
      testDatabasePassword = "test pass:$dollar:quote':colon\\backslash";
      backupRestoreSecrets = pkgs.writeText "teslamate-backup-test.env" ''
        DATABASE_PASS="${testDatabasePassword}"
      '';
      missingPasswordSecrets = pkgs.writeText "teslamate-backup-test-missing-password.env" ''
        RELEASE_COOKIE=test
      '';
      fakePostgresql = pkgs.symlinkJoin {
        name = "fake-postgresql";
        paths = [
          (pkgs.writeShellScriptBin "pg_dump" ''
            set -euo pipefail
            : "''${FAKE_PG_LOG:?'FAKE_PG_LOG must be set'}"
            : "''${EXPECTED_DATABASE_PASSWORD:?'EXPECTED_DATABASE_PASSWORD must be set'}"

            if [ "''${PGPASSWORD:-}" != "$EXPECTED_DATABASE_PASSWORD" ]; then
              echo "pg_dump did not receive the expected database password" >&2
              exit 90
            fi

            printf '%s\n' "pg_dump-call" >> "$FAKE_PG_LOG"
            for argument in "$@"; do
              printf 'pg_dump-arg=%s\n' "$argument" >> "$FAKE_PG_LOG"
            done
            printf '%s\n' "backup data"
          '')
          (pkgs.writeShellScriptBin "psql" ''
            set -euo pipefail
            : "''${FAKE_PG_LOG:?'FAKE_PG_LOG must be set'}"
            : "''${EXPECTED_DATABASE_PASSWORD:?'EXPECTED_DATABASE_PASSWORD must be set'}"

            if [ "''${PGPASSWORD:-}" != "$EXPECTED_DATABASE_PASSWORD" ]; then
              echo "psql did not receive the expected database password" >&2
              exit 91
            fi

            input="$(cat)"
            if [[ "$input" == *"DROP SCHEMA"* ]]; then
              operation=reset
            else
              operation=restore
            fi

            printf 'psql-call=%s\n' "$operation" >> "$FAKE_PG_LOG"
            for argument in "$@"; do
              printf 'psql-arg=%s\n' "$argument" >> "$FAKE_PG_LOG"
            done

            if [ "''${FAKE_PSQL_FAIL:-}" = "$operation" ]; then
              exit "''${FAKE_PSQL_STATUS:-23}"
            fi
          '')
        ];
      };
      fakeSystemd = pkgs.writeShellScriptBin "systemctl" ''
        set -euo pipefail
        : "''${FAKE_SYSTEMCTL_LOG:?'FAKE_SYSTEMCTL_LOG must be set'}"

        printf 'systemctl-arg=%s\n' "$*" >> "$FAKE_SYSTEMCTL_LOG"

        case "''${1:-}" in
          stop) exit "''${FAKE_SYSTEMCTL_STOP_STATUS:-0}" ;;
          start) exit "''${FAKE_SYSTEMCTL_START_STATUS:-0}" ;;
          *) exit 92 ;;
        esac
      '';
      makeBackupRestore =
        environmentFilePath:
        pkgs.callPackage ../backup_and_restore.nix {
          postgresql = fakePostgresql;
          systemd = fakeSystemd;
          databaseUser = "custom_role";
          databaseName = "custom_database";
          databaseHost = "db.example.test";
          databasePort = 6543;
          inherit environmentFilePath;
        };
      backupRestore = makeBackupRestore backupRestoreSecrets;
      backupRestoreMissingPassword = makeBackupRestore missingPasswordSecrets;
      backupRestoreScriptsTest = pkgs.runCommand "backup-restore-scripts-test" { } ''
        export EXPECTED_DATABASE_PASSWORD=${lib.escapeShellArg testDatabasePassword}
        export FAKE_PG_LOG="$PWD/pg.log"
        export FAKE_SYSTEMCTL_LOG="$PWD/systemctl.log"
        touch "$FAKE_PG_LOG" "$FAKE_SYSTEMCTL_LOG"

        if ${backupRestore}/bin/teslamate-restore "$PWD/does-not-exist.sql" 2> "$PWD/missing-file.log"; then
          echo "restore unexpectedly succeeded with a missing input file" >&2
          exit 1
        fi
        grep -F "does not exist, is not a regular file, or is not readable" "$PWD/missing-file.log"
        test ! -s "$FAKE_PG_LOG"
        test ! -s "$FAKE_SYSTEMCTL_LOG"

        ${backupRestore}/bin/teslamate-backup "$PWD/backup.sql"
        grep -Fx "backup data" "$PWD/backup.sql"
        grep -Fx "pg_dump-arg=--host=db.example.test" "$FAKE_PG_LOG"
        grep -Fx "pg_dump-arg=--port=6543" "$FAKE_PG_LOG"
        grep -Fx "pg_dump-arg=--username=custom_role" "$FAKE_PG_LOG"
        grep -Fx "pg_dump-arg=--dbname=custom_database" "$FAKE_PG_LOG"
        grep -Fx "pg_dump-arg=--no-password" "$FAKE_PG_LOG"

        printf '%s\n' "restored data" > "$PWD/restore.sql"
        ${backupRestore}/bin/teslamate-restore "$PWD/restore.sql"
        test "$(grep -Fc "psql-arg=--host=db.example.test" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "psql-arg=--port=6543" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "psql-arg=--username=custom_role" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "psql-arg=--dbname=custom_database" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "psql-arg=--no-password" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "psql-arg=--set=ON_ERROR_STOP=1" "$FAKE_PG_LOG")" -eq 2
        test "$(grep -Fc "systemctl-arg=stop teslamate.service" "$FAKE_SYSTEMCTL_LOG")" -eq 1
        test "$(grep -Fc "systemctl-arg=start teslamate.service" "$FAKE_SYSTEMCTL_LOG")" -eq 1

        if grep -F "$EXPECTED_DATABASE_PASSWORD" "$FAKE_PG_LOG"; then
          echo "database password leaked into PostgreSQL command arguments" >&2
          exit 1
        fi
        if grep -F "$EXPECTED_DATABASE_PASSWORD" "$(readlink -f ${backupRestore}/bin/teslamate-backup)"; then
          echo "database password leaked into the generated backup script" >&2
          exit 1
        fi
        if grep -F "$EXPECTED_DATABASE_PASSWORD" "$(readlink -f ${backupRestore}/bin/teslamate-restore)"; then
          echo "database password leaked into the generated restore script" >&2
          exit 1
        fi

        : > "$FAKE_PG_LOG"
        : > "$FAKE_SYSTEMCTL_LOG"
        export FAKE_SYSTEMCTL_STOP_STATUS=43
        if ${backupRestore}/bin/teslamate-restore "$PWD/restore.sql"; then
          echo "restore unexpectedly succeeded when TeslaMate failed to stop" >&2
          exit 1
        else
          status="$?"
        fi
        test "$status" -eq 43
        test ! -s "$FAKE_PG_LOG"
        grep -Fx "systemctl-arg=stop teslamate.service" "$FAKE_SYSTEMCTL_LOG"
        grep -Fx "systemctl-arg=start teslamate.service" "$FAKE_SYSTEMCTL_LOG"
        unset FAKE_SYSTEMCTL_STOP_STATUS

        : > "$FAKE_PG_LOG"
        : > "$FAKE_SYSTEMCTL_LOG"
        export FAKE_SYSTEMCTL_START_STATUS=42
        if ${backupRestore}/bin/teslamate-restore "$PWD/restore.sql"; then
          echo "restore unexpectedly succeeded when TeslaMate failed to restart" >&2
          exit 1
        else
          status="$?"
        fi
        test "$status" -eq 42
        grep -Fx "systemctl-arg=stop teslamate.service" "$FAKE_SYSTEMCTL_LOG"
        grep -Fx "systemctl-arg=start teslamate.service" "$FAKE_SYSTEMCTL_LOG"

        : > "$FAKE_PG_LOG"
        : > "$FAKE_SYSTEMCTL_LOG"
        export FAKE_PSQL_FAIL=reset
        export FAKE_PSQL_STATUS=23
        export FAKE_SYSTEMCTL_START_STATUS=41
        if ${backupRestore}/bin/teslamate-restore "$PWD/restore.sql"; then
          echo "restore unexpectedly succeeded when database reset failed" >&2
          exit 1
        else
          status="$?"
        fi
        test "$status" -eq 23
        grep -Fx "systemctl-arg=stop teslamate.service" "$FAKE_SYSTEMCTL_LOG"
        grep -Fx "systemctl-arg=start teslamate.service" "$FAKE_SYSTEMCTL_LOG"

        : > "$FAKE_PG_LOG"
        : > "$FAKE_SYSTEMCTL_LOG"
        export FAKE_PSQL_FAIL=restore
        export FAKE_PSQL_STATUS=24
        unset FAKE_SYSTEMCTL_START_STATUS
        if ${backupRestore}/bin/teslamate-restore "$PWD/restore.sql"; then
          echo "restore unexpectedly succeeded when psql restore failed" >&2
          exit 1
        else
          status="$?"
        fi
        test "$status" -eq 24
        grep -Fx "systemctl-arg=stop teslamate.service" "$FAKE_SYSTEMCTL_LOG"
        grep -Fx "systemctl-arg=start teslamate.service" "$FAKE_SYSTEMCTL_LOG"

        : > "$FAKE_PG_LOG"
        : > "$FAKE_SYSTEMCTL_LOG"
        unset FAKE_PSQL_FAIL FAKE_PSQL_STATUS
        if ${backupRestoreMissingPassword}/bin/teslamate-backup "$PWD/missing.sql" 2> "$PWD/missing-backup.log"; then
          echo "backup unexpectedly succeeded without DATABASE_PASS" >&2
          exit 1
        fi
        grep -F "DATABASE_PASS must be set" "$PWD/missing-backup.log"
        test ! -s "$FAKE_PG_LOG"

        if ${backupRestoreMissingPassword}/bin/teslamate-restore "$PWD/restore.sql" 2> "$PWD/missing-restore.log"; then
          echo "restore unexpectedly succeeded without DATABASE_PASS" >&2
          exit 1
        fi
        grep -F "DATABASE_PASS must be set" "$PWD/missing-restore.log"
        test ! -s "$FAKE_PG_LOG"
        test ! -s "$FAKE_SYSTEMCTL_LOG"

        touch $out
      '';
      moduleTest =
        (nixpkgs.lib.nixos.runTest {
          hostPkgs = pkgs;
          defaults.documentation.enable = false;
          imports = [
            {
              name = "teslamate";
              nodes.server = {
                imports = [ self.nixosModules.default ];
                virtualisation.cores = 4;
                virtualisation.memorySize = 2048;

                services.teslamate = {
                  enable = true;
                  secretsFile = builtins.toFile "teslamate.env" ''
                    ENCRYPTION_KEY=123456789
                    DATABASE_PASS=123456789
                    RELEASE_COOKIE=123456789
                  '';
                  postgres.enable_server = true;
                  grafana.enable = true;
                };
              };

              testScript = ''
                server.wait_for_open_port(4000)
              '';
            }
          ];
        }).config.result;
    in
    {
      checks =
        if pkgs.stdenv.isLinux then
          {
            backup-restore-scripts = backupRestoreScriptsTest;
            default = moduleTest;
            maintenance-scripts = maintenanceScriptsTest;
          }
        else
          { };
    };
}
