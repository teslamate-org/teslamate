#!/usr/bin/env bash

# The script assumes that basic authentication is configured
# (change the login credentials with `LOGIN`).
#
# DASHBOARD_DIRECTORY represents the path to the directory
# where the JSON files corresponding to the dashboards exist.
# The default location is relative to the execution of the
# script.
#
# URL specifies the URL of the Grafana instance.
#
# Source: https://github.com/cirocosta/sample-grafana/blob/master/update-dashboards.sh

set -o errexit

readonly URL=${URL:-"http://localhost:3000"}
readonly LOGIN=${LOGIN:-"admin:admin"}
readonly DASHBOARDS_DIRECTORY=${DASHBOARDS_DIRECTORY:-"./grafana/dashboards"}


main() {
  local task=$1

  echo "
URL:                  $URL
LOGIN:                $LOGIN
DASHBOARDS_DIRECTORY: $DASHBOARDS_DIRECTORY
  "

  case $task in
      backup) backup;;
      restore) restore;;
      *)     exit 1;;
  esac

}


backup() {
  local dashboard_json

  for dashboard in $(list_dashboards); do
    dashboard_json=$(get_dashboard "$dashboard")

    if [[ -z "$dashboard_json" ]]; then
      echo "ERROR:
  Couldn't retrieve dashboard $dashboard.
      "
      exit 1
    fi

    echo "$dashboard_json" > "$DASHBOARDS_DIRECTORY/$dashboard".json

    echo "BACKED UP $(basename "$dashboard").json"
  done
}


restore() {
  find "$DASHBOARDS_DIRECTORY" -type f -name \*.json -print0 |
      while IFS= read -r -d '' dashboard_path; do
          folder_id=$(get_folder_id "$(basename "$dashboard_path" .json)")
          curl \
            --silent --show-error --output /dev/null \
            --user "$LOGIN" \
            -X POST -H "Content-Type: application/json" \
            -d "{\"dashboard\":$(cat "$dashboard_path"), \
                    \"overwrite\":true, \
                    \"folderId\":$folder_id, \
                    \"inputs\":[{\"name\":\"DS_CLOUDWATCH\", \
                                 \"type\":\"datasource\", \
                                 \"pluginId\":\"cloudwatch\", \
                                 \"value\":\"TeslaMate\"}]}" \
            "$URL/api/dashboards/import"

          echo "RESTORED $(basename "$dashboard_path")"
      done
}

get_dashboard() {
  local dashboard=$1

  if [[ -z "$dashboard" ]]; then
    echo "ERROR:
  A dashboard must be specified.
  "
    exit 1
  fi

  curl \
    --silent \
    --user "$LOGIN" \
    "$URL/api/dashboards/db/$dashboard" |
    jq '.dashboard | .id = null'
}

get_folder_id() {
  local dashboard=$1

  if [[ -z "$dashboard" ]]; then
    echo "ERROR:
  A dashboard must be specified.
  "
    exit 1
  fi

  curl \
    --silent \
    --user "$LOGIN" \
    "$URL/api/dashboards/db/$dashboard" |
    jq '.meta | .folderId'
}

list_dashboards() {
  curl \
    --silent \
    --user "$LOGIN" \
    "$URL/api/search" |
    jq -r '.[] | select(.type == "dash-db") | .uri' |
    cut -d '/' -f2
}


main "$@"
