{ stdenv
, lib
, pkgs
, writeShellScript
, databaseUser
, databaseName
, ...
}:
let
  backup = writeShellScript "teslamate-backup" ''
    set -euo pipefail
    : ''${1?' Please specify a file to save backup'}
    sudo -u teslamate pg_dump -U ${databaseUser} ${databaseName} > "$1"
  '';
  restore = writeShellScript "teslamate-restore" ''
    set -euo pipefail
    : ''${1?' Please specify a file to restore from'}

    # Stop the teslamate service to avoid write conflicts
    systemctl stop teslamate.service

    # Drop existing data and reinitialize
    sudo -u teslamate psql -U ${databaseUser} << .
      drop schema public cascade;
      create schema public;
      CREATE EXTENSION cube WITH SCHEMA public;
      CREATE EXTENSION earthdistance WITH SCHEMA public;
    .

    # Restore
    sudo -u teslamate psql -U ${databaseUser} -d ${databaseName} < "$1"

    # Restart the teslamate container
    systemctl start teslamate.service
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
