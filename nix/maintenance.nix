{
  stdenv,
  lib,
  pkgs,
  writeShellScript,
  getExe,
  teslamate,
  environmentFilePath,
  ...
}:
let
  # Extract a single KEY=value from the environment file literally, without
  # sourcing it. Sourcing would execute the file as a shell script (arbitrary
  # code execution if a secret contains e.g. $(...) or backticks) and break on
  # values containing quotes. sed prints everything after the first '=' as-is,
  # so the value may contain any character (single quotes, spaces, $, ...).
  # tail -n1 mirrors systemd's "last assignment wins" for duplicate keys.
  #
  # The env file wraps values in double quotes (e.g. RELEASE_COOKIE="..."), so
  # we strip one optional surrounding pair afterwards. The inner value is left
  # untouched and may still contain anything.
  loadFromEnvFile = key: ''
    if [ ! -f ${environmentFilePath} ]; then
      echo "Environment file ${environmentFilePath} not found!" >&2
      exit 1
    fi
    ${key}="$(sed -n 's/^${key}=//p' ${environmentFilePath} | tail -n1)"
    ${key}="''${${key}#\"}"
    ${key}="''${${key}%\"}"
    export ${key}
  '';

  closeDrive = writeShellScript "teslamate-close-drive" ''
    set -euo pipefail
    : ''${1?'Please provide a drive ID to close'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Drive ID must be an integer." >&2
      exit 1
    fi

    # load RELEASE_COOKIE from the env file
    ${loadFromEnvFile "RELEASE_COOKIE"}
    : ''${RELEASE_COOKIE:?'RELEASE_COOKIE must be set in the environment file'}

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

    # load RELEASE_COOKIE from the env file
    ${loadFromEnvFile "RELEASE_COOKIE"}
    : ''${RELEASE_COOKIE:?'RELEASE_COOKIE must be set in the environment file'}

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

    # load RELEASE_COOKIE from the env file
    ${loadFromEnvFile "RELEASE_COOKIE"}
    : ''${RELEASE_COOKIE:?'RELEASE_COOKIE must be set in the environment file'}

    echo "Attempt to delete the drive with ID ''${1}."
    case "$(${getExe teslamate} rpc "TeslaMate.Log.delete_drive(''${1})")" in
      :ok)
        echo "Successfully deleted drive with ID ''${1}."
        ;;
      :not_found)
        echo "Warning: Drive with ID ''${1} does not exist. Nothing to delete." >&2
        ;;
      *)
        echo "Error: Failed to delete drive with ID ''${1}." >&2
        exit 1
        ;;
    esac
  '';

  deleteCharge = writeShellScript "teslamate-delete-charge" ''
    set -euo pipefail
    : ''${1?'Please provide a charge ID to delete'}

    if ! [[ "''${1}" =~ ^[0-9]+$ ]]; then
      echo "Error: Charge ID must be an integer." >&2
      exit 1
    fi

    # load RELEASE_COOKIE from the env file
    ${loadFromEnvFile "RELEASE_COOKIE"}
    : ''${RELEASE_COOKIE:?'RELEASE_COOKIE must be set in the environment file'}

    echo "Attempt to delete the charge with ID ''${1}."
    case "$(${getExe teslamate} rpc "TeslaMate.Log.delete_charging_process(''${1})")" in
      :ok)
        echo "Successfully deleted charging process with ID ''${1}."
        ;;
      :not_found)
        echo "Warning: Charging process with ID ''${1} does not exist. Nothing to delete." >&2
        ;;
      *)
        echo "Error: Failed to delete charging process with ID ''${1}." >&2
        exit 1
        ;;
    esac
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
