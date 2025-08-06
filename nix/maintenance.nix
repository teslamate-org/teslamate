{ stdenv
, lib
, pkgs
, writeShellScript
, databaseUser
, databaseName
, getExe
, teslamate
, environmentFilePath
, ...
}:
let
  closeDrive = writeShellScript "teslamate-close-drive" ''
    set -euo pipefail
    : ''${1?'Please provide a drive ID to close'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Drive ID must be an integer." >&2
      exit 1
    fi

    # load env file to have RELEASE_COOKIE set
    if [ -f ${environmentFilePath} ]; then
      source ${environmentFilePath}
      export RELEASE_COOKIE
    else
      echo "Environment file ${environmentFilePath} not found!" >&2
      exit 1
    fi
    : ''${RELEASE_COOKIE?'RELEASE_COOKIE must be set in the environment file'}

    echo "Attempt to close the drive with ID ''${1}."
    ${getExe teslamate} rpc "TeslaMate.Repo.get!(TeslaMate.Log.Drive, ''${1}) |> TeslaMate.Log.close_drive()"
  '';

  closeCharge = writeShellScript "teslamate-close-charge" ''
    set -euo pipefail
    : ''${1?'Please provide a charge ID to close'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Charge ID must be an integer." >&2
      exit 1
    fi

    # load env file to have RELEASE_COOKIE set
    if [ -f ${environmentFilePath} ]; then
      source ${environmentFilePath}
      export RELEASE_COOKIE
    else
      echo "Environment file ${environmentFilePath} not found!" >&2
      exit 1
    fi
    : ''${RELEASE_COOKIE?'RELEASE_COOKIE must be set in the environment file'}

    echo "Attempt to close the charge with ID ''${1}."
    ${getExe teslamate} rpc "TeslaMate.Repo.get!(TeslaMate.Log.ChargingProcess, ''${1}) |> TeslaMate.Log.complete_charging_process()"
  '';

  deleteDrive = writeShellScript "teslamate-delete-drive" ''
    set -euo pipefail
    : ''${1?'Please provide a drive ID to delete'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Drive ID must be an integer." >&2
      exit 1
    fi

    # Check if drive exists
    if [ "$(sudo -u teslamate psql -U ${databaseUser} -d ${databaseName} -tAc "SELECT 1 FROM drives WHERE id = ''${1};")" != "1" ]; then
      echo "Warning: Drive with ID ''${1} does not exist. Nothing to delete." >&2
      exit 0
    fi

    echo "Attempt to delete the drive with ID ''${1}."
    sudo -u teslamate psql -U ${databaseUser} -d ${databaseName} -c "DELETE FROM drives WHERE id = ''${1};"
    echo "Successfully deleted drive with ID ''${1}."
  '';

  deleteCharge = writeShellScript "teslamate-delete-charge" ''
    set -euo pipefail
    : ''${1?'Please provide a charge ID to delete'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Charge ID must be an integer." >&2
      exit 1
    fi

    # Check if charging process exists
    if [ "$(sudo -u teslamate psql -U ${databaseUser} -d ${databaseName} -tAc "SELECT 1 FROM charging_processes WHERE id = ''${1};")" != "1" ]; then
      echo "Warning: Charging process with ID ''${1} does not exist. Nothing to delete." >&2
      exit 0
    fi

    echo "Attempt to delete the charge with ID ''${1}."
    sudo -u teslamate psql -U ${databaseUser} -d ${databaseName} -c "DELETE FROM charging_processes WHERE id = ''${1};"
    echo "Successfully deleted charging process with ID ''${1}."
  '';
in
stdenv.mkDerivation {
  pname = "teslamate-maintenance";
  version = "0.1.0";
  src = ./.;

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${closeDrive} $out/bin/teslamate-close-drive
    ln -s ${closeCharge} $out/bin/teslamate-close-charge
    ln -s ${deleteDrive} $out/bin/teslamate-delete-drive
    ln -s ${deleteCharge} $out/bin/teslamate-delete-charge
  '';
}
