{
  stdenv,
  lib,
  coreutils,
  gnused,
  postgresql,
  systemd,
  writeShellScript,
  databaseUser,
  databaseName,
  databaseHost,
  databasePort,
  environmentFilePath,
  ...
}:
let
  pgDump = lib.getExe' postgresql "pg_dump";
  psql = lib.getExe' postgresql "psql";
  sed = lib.getExe gnused;
  systemctl = lib.getExe' systemd "systemctl";
  tail = lib.getExe' coreutils "tail";
  databaseArgs = lib.escapeShellArgs [
    "--host=${databaseHost}"
    "--port=${toString databasePort}"
    "--username=${databaseUser}"
    "--dbname=${databaseName}"
    "--no-password"
  ];
  loadDatabasePassword = ''
    load_database_password() {
      if [ ! -r ${lib.escapeShellArg environmentFilePath} ]; then
        printf '%s\n' ${lib.escapeShellArg "Environment file ${environmentFilePath} not found or not readable."} >&2
        return 1
      fi

      database_password="$(
        ${sed} -n 's/^DATABASE_PASS=//p' ${lib.escapeShellArg environmentFilePath} |
          ${tail} -n 1
      )"

      case "$database_password" in
        \"*\")
          database_password="''${database_password#\"}"
          database_password="''${database_password%\"}"
          ;;
      esac

      if [ -z "$database_password" ]; then
        printf '%s\n' ${lib.escapeShellArg "DATABASE_PASS must be set in ${environmentFilePath} (services.teslamate.secretsFile)."} >&2
        return 1
      fi
    }

    run_with_database_password() {
      PGPASSWORD="$database_password" "$@"
    }
  '';
  backup = writeShellScript "teslamate-backup" ''
    set -euo pipefail
    : "''${1:?'Please specify a file to save backup'}"

    ${loadDatabasePassword}
    load_database_password
    run_with_database_password ${pgDump} ${databaseArgs} > "$1"
  '';
  restore = writeShellScript "teslamate-restore" ''
    set -euo pipefail
    : "''${1:?'Please specify a file to restore from'}"

    if [ ! -f "$1" ]; then
      printf 'Restore file %q does not exist, is not a regular file, or is not readable.\n' "$1" >&2
      exit 1
    fi
    if ! exec 3< "$1"; then
      printf 'Restore file %q does not exist, is not a regular file, or is not readable.\n' "$1" >&2
      exit 1
    fi

    ${loadDatabasePassword}
    load_database_password

    restart_teslamate() {
      original_status="$?"
      trap - EXIT

      if ${systemctl} start teslamate.service 3<&-; then
        restart_status=0
      else
        restart_status="$?"
      fi

      if [ "$original_status" -ne 0 ]; then
        exit "$original_status"
      fi

      exit "$restart_status"
    }

    # Restart TeslaMate on every exit after this point. If reset or restore
    # fails, preserve that original status even when restarting also fails.
    trap restart_teslamate EXIT

    ${systemctl} stop teslamate.service 3<&-

    # Drop existing data and reinitialize
    run_with_database_password ${psql} ${databaseArgs} --set=ON_ERROR_STOP=1 <<'SQL'
    DROP SCHEMA IF EXISTS public CASCADE;
    DROP SCHEMA IF EXISTS private CASCADE;
    CREATE SCHEMA public;
    CREATE EXTENSION cube WITH SCHEMA public;
    CREATE EXTENSION earthdistance WITH SCHEMA public;
    SQL

    # Restore
    run_with_database_password ${psql} ${databaseArgs} --set=ON_ERROR_STOP=1 <&3
  '';
in
stdenv.mkDerivation {
  pname = "teslamate-backup";
  version = "0.1.0";
  src = ./.;

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${backup} $out/bin/teslamate-backup
    ln -s ${restore} $out/bin/teslamate-restore
  '';
}
