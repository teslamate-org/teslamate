#!/usr/bin/env bash

# The script requires an API token. See
# https://grafana.com/docs/grafana-cloud/security-and-account-management/authentication-and-permissions/service-accounts/#add-a-token-to-a-service-account-in-grafana
# how to create a token using the Grafana UI or API.
# Set the Grafana API token with GRAFANA_API_TOKEN.
#
# DASHBOARD_DIRECTORY represents the path to the directory
# where the JSON files corresponding to the dashboards exist.
# The default location is relative to the execution of the
# script.
#
# URL specifies the URL of the Grafana instance.
# GRAFANA_ORG_NAMESPACE specifies the Grafana namespace to use for API calls (defaults to "default").

set -o errexit

readonly URL=${URL:-"http://localhost:3000"}
readonly GRAFANA_API_TOKEN=${GRAFANA_API_TOKEN:-"your_api_token_here"}
readonly DASHBOARDS_DIRECTORY=${DASHBOARDS_DIRECTORY:-"./grafana/dashboards"}
readonly GRAFANA_ORG_NAMESPACE=${GRAFANA_ORG_NAMESPACE:-"default"}
API_VERSION="v1beta1"

slugify() {
	local input_string=$1
	local slug

	# Convert to lowercase
	slug=$(echo "$input_string" | tr '[:upper:]' '[:lower:]')

	# Replace spaces and underscores with hyphens
	slug=${slug//[ _]/-}

	# Remove any character that is not alphanumeric or a hyphen
	slug=${slug//[^a-z0-9-]/}

	# Remove leading hyphens
	slug=${slug##-}
	# Remove trailing hyphens
	slug=${slug%%-}

	echo "$slug"
}

main() {
	local task=$1

	echo "
URL:                    $URL
GRAFANA_API_TOKEN:      $GRAFANA_API_TOKEN
DASHBOARDS_DIRECTORY:   $DASHBOARDS_DIRECTORY
GRAFANA_ORG_NAMESPACE:  $GRAFANA_ORG_NAMESPACE
  "

	case $task in
	backup) backup ;;
	restore) restore ;;
	*) exit 1 ;;
	esac

}

backup() {
	local dashboard_info_json
	local dashboard_uid
	local dashboard_title
	local initial_folder_uid
	local grafana_path_array_str
	local -a grafana_path_array # Declare as array
	local dashboard_json
	local target_dir
	local filename

	echo "Starting dashboard backup process (scoped to 'TeslaMate' folder and its subfolders)..."
	mkdir -p "$DASHBOARDS_DIRECTORY" # Ensure base directory exists

	list_dashboards | while IFS= read -r dashboard_info_json; do
		dashboard_uid="$(echo "$dashboard_info_json" | jq -r '.uid')"
		dashboard_title="$(echo "$dashboard_info_json" | jq -r '.title')"
		initial_folder_uid="$(echo "$dashboard_info_json" | jq -r '.folderUid // empty')" # Ensure empty string if null

		if [[ -z $dashboard_title || $dashboard_title == "null" ]]; then
			echo "WARNING: Dashboard with UID $dashboard_uid has no title, skipping backup." >&2
			continue
		fi
		if [[ -z $dashboard_uid || $dashboard_uid == "null" ]]; then
			echo "WARNING: Found dashboard with no UID (Title: $dashboard_title), skipping backup." >&2
			continue
		fi

		if [[ -z $initial_folder_uid ]]; then
			# echo "INFO: Dashboard '$dashboard_title' (UID: $dashboard_uid) is not in a folder, skipping."
			continue # Skip dashboards not in any folder
		fi

		grafana_path_array_str=$(build_grafana_folder_path_array "$initial_folder_uid")
		# Convert space-separated string to bash array
		read -r -a grafana_path_array <<<"$grafana_path_array_str"

		if [[ ${#grafana_path_array[@]} -eq 0 || ${grafana_path_array[0]} != "teslamate" ]]; then
			# Folder path couldn't be determined, or it's not under "TeslaMate"
			# echo "INFO: Dashboard '$dashboard_title' (UID: $dashboard_uid) is not under 'TeslaMate' folder (path: $grafana_path_array_str), skipping."
			continue
		fi

		# Construct local save path (remove "TeslaMate" from the path components)
		local -a local_save_path_parts=()
		if ((${#grafana_path_array[@]} > 1)); then
			local_save_path_parts=("${grafana_path_array[@]:1}") # All elements except the first
		fi

		target_dir="$DASHBOARDS_DIRECTORY"
		if ((${#local_save_path_parts[@]} > 0)); then
			relative_save_path=$(
				IFS=/
				echo "${local_save_path_parts[*]}"
			)
			# Further sanitize relative_save_path if folder titles can have problematic chars for dir names
			target_dir="$DASHBOARDS_DIRECTORY/$relative_save_path"
		fi

		mkdir -p "$target_dir"
		filename="$(slugify "$dashboard_title").json"
		if [[ -z ${filename%%.json} ]]; then
			filename="dashboard.json"
		fi

		#echo "INFO: Backing up Grafana dashboard '$dashboard_title' (UID: $dashboard_uid) from Grafana path '$grafana_path_array_str' to local path '$target_dir/$filename'"
		dashboard_json=$(get_dashboard "$dashboard_uid")

		if [[ -z $dashboard_json ]]; then
			echo "ERROR: Couldn't retrieve dashboard spec for '$dashboard_title' (UID: $dashboard_uid)." >&2
			continue
		fi

		echo "$dashboard_json" >"$target_dir/$filename"
		echo "BACKED UP: $target_dir/$filename (UID: $dashboard_uid)"
	done
	echo "Dashboard backup process completed."
}

restore() {
	find "$DASHBOARDS_DIRECTORY" -type f -name \*.json -print0 |
		while IFS= read -r -d '' dashboard_path; do
			relative_file_path="${dashboard_path#"$DASHBOARDS_DIRECTORY"/}"
			local_subfolder_path=$(dirname "$relative_file_path")

			local -a target_grafana_folder_titles_array=()
			target_grafana_folder_titles_array+=("TeslaMate") # Always start with TeslaMate

			if [[ $local_subfolder_path != "." && -n $local_subfolder_path ]]; then
				local old_ifs=$IFS
				IFS='/'
				# shellcheck disable=SC2206 # Word splitting is desired here
				local path_parts_for_restore=($local_subfolder_path)
				IFS=$old_ifs
				target_grafana_folder_titles_array+=("${path_parts_for_restore[@]}")
			fi

			local leaf_folder_to_assign_dashboard_uid=""
			#local current_grafana_parent_uid=""
			local folder_creation_failed=false

			#echo "INFO: Ensuring Grafana folder hierarchy for local path '$local_subfolder_path': ($(IFS=/ ; echo "${target_grafana_folder_titles_array[*]}"))"

			for title_part in "${target_grafana_folder_titles_array[@]}"; do
				if [[ -z $title_part ]]; then continue; fi

				# Capitalize the first letter of the title part (e.g. "internal" -> "Internal")
				title_part=$(tr '[:lower:]' '[:upper:]' <<<"${title_part:0:1}")${title_part:1}

				#echo "INFO: Processing Grafana folder part: '$title_part'"
				current_folder_uid=$(get_folder_uid_by_title "$title_part")

				if [[ -z $current_folder_uid ]]; then
					echo "INFO: Grafana folder '$title_part' not found, attempting to create."
					current_folder_uid=$(create_folder "$title_part") # This creates at root.
					if [[ -z $current_folder_uid ]]; then
						echo "ERROR: Failed to create Grafana folder '$title_part'. Skipping dashboard $(basename "$dashboard_path")." >&2
						folder_creation_failed=true
						break
					else
						echo "INFO: Successfully created Grafana folder '$title_part' with UID '$current_folder_uid'."
					fi
					#else
					#echo "INFO: Found existing Grafana folder '$title_part' with UID '$current_folder_uid'."
				fi
				leaf_folder_to_assign_dashboard_uid="$current_folder_uid"
				# current_grafana_parent_uid="$current_folder_uid" # This would be for true nesting if helpers supported it
			done

			if [[ $folder_creation_failed == true ]]; then
				continue
			fi

			if [[ -z $leaf_folder_to_assign_dashboard_uid ]]; then
				echo "ERROR: Could not determine a target Grafana folder UID for dashboard $(basename "$dashboard_path"). Skipping." >&2
				continue
			fi

			local folder_uid="$leaf_folder_to_assign_dashboard_uid" # Use this for the payload

			dashboard_json_content=$(cat "$dashboard_path")
			extracted_uid="$(echo "$dashboard_json_content" | jq -r '.uid // empty')"
			# Detect file format and extract relevant fields
			if echo "$dashboard_json_content" | jq -e 'has("spec")' >/dev/null; then
				spec_obj="$(echo "$dashboard_json_content" | jq '.spec')"
				extracted_uid="$(echo "$dashboard_json_content" | jq -r '.metadata.name // empty')"
			else
				spec_obj="$dashboard_json_content"
				extracted_uid="$(echo "$dashboard_json_content" | jq -r '.uid // empty')"
			fi
			# Extract dashboard_title from the JSON content for use in name_prefix
			local dashboard_title
			dashboard_title="$(echo "$dashboard_json_content" | jq -r '.title // empty')"

			local name_prefix=""
			if [[ -n $dashboard_title && $dashboard_title != "null" && $dashboard_title != "empty" ]]; then
				name_prefix="$(slugify "$dashboard_title")"
				if [[ -z $name_prefix ]]; then
					name_prefix="dashboard-prefix"
				fi
			else
				name_prefix="dashboard-prefix"
			fi

			http_method=""
			api_endpoint=""

			# Try to get the dashboard with the extracted_uid (if present)
			schema_version=""
			if [[ -n $extracted_uid ]]; then
				existing_dashboard_json=$(curl --silent --fail -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
					"$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards/$extracted_uid" || true)
				if [[ -n $existing_dashboard_json ]]; then
					# Dashboard exists, extract schemaVersion and increment
					schema_version=$(echo "$existing_dashboard_json" | jq -r '.spec.schemaVersion // empty')
					if [[ -n $schema_version && $schema_version =~ ^[0-9]+$ ]]; then
						schema_version=$((schema_version + 1))
						# Inject incremented schemaVersion into spec_obj
						#spec_obj=$(echo "$spec_obj" | jq --argjson v "$schema_version" '.schemaVersion = $v')
					fi
					http_method="PUT"
					api_endpoint="$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards/$extracted_uid"
				else
					# Dashboard does not exist, use POST to create
					http_method="POST"
					api_endpoint="$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards"
				fi
			else
				http_method="POST"
				api_endpoint="$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards"
			fi

			final_payload=$(jq -n --argjson spec_obj "$spec_obj" \
				--arg name "${extracted_uid:-null}" \
				--arg folder_uid "${folder_uid:-null}" \
				--arg name_prefix "$name_prefix" \
				'{
                "metadata": (
                    (if $name != "null" and $name != "" then {name: $name} else {generateName: ($name_prefix + "-")} end) +
                    (if $folder_uid != "null" and $folder_uid != "" then {annotations: {"grafana.app/folder": $folder_uid, "grafana.app/message": "restore"}} else {annotations: {"grafana.app/message": "restore"}} end)
                ),
                "spec": $spec_obj
            }')

			curl \
				--silent --fail --show-error --output /dev/null \
				-H "Authorization: Bearer $GRAFANA_API_TOKEN" \
				-X "$http_method" -H "Content-Type: application/json" \
				-d "$final_payload" \
				"$api_endpoint"

			echo "RESTORED $(basename "$dashboard_path") into Grafana folder '${target_grafana_folder_titles_array[-1]}' (UID: $leaf_folder_to_assign_dashboard_uid) (Conceptual path: $(
				IFS=/
				echo "${target_grafana_folder_titles_array[*]}"
			))"
		done
}

get_dashboard() {
	local dashboard_uid=$1

	if [[ -z $dashboard_uid ]]; then
		echo "ERROR: A dashboard UID must be specified." >&2 # Log to stderr
		exit 1
	fi

	curl \
		--silent --fail --show-error \
		-H "Authorization: Bearer $GRAFANA_API_TOKEN" \
		"$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards/$dashboard_uid" |
		jq
}

get_folder_uid_by_title() {
	local folder_title=$1
	local folder_uid

	folder_uid=$(curl --silent --fail --show-error -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
		"$URL/apis/folder.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/folders" |
		jq -r --arg title "$folder_title" '.items[]? | select(.spec.title == $title) | .metadata.name // empty')

	echo "$folder_uid"
}

get_folder_path_details() {
	local folder_uid_to_lookup=$1
	local folder_details_json

	if [[ -z $folder_uid_to_lookup ]]; then
		echo "{}" # Return empty JSON if no UID
		return
	fi

	local jq_query
	jq_query='{title: (.spec.title // ""), parentUid: (.metadata.annotations."grafana.app/folder" // "")}'

	folder_details_json=$(curl --silent --fail --show-error \
		-H "Authorization: Bearer $GRAFANA_API_TOKEN" \
		"$URL/apis/folder.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/folders/$folder_uid_to_lookup" |
		jq -c "$jq_query")

	if [[ -z $folder_details_json || $folder_details_json == "null" ]]; then
		echo "{}" # Default to empty JSON on error or no data
	else
		echo "$folder_details_json"
	fi
}

build_grafana_folder_path_array() {
	local current_folder_uid=$1
	local path_components=() # Array to store folder titles
	local folder_details_json
	local title
	local parent_uid

	# Max depth to prevent infinite loops in case of unexpected API responses or circular refs
	local max_depth=10
	local current_depth=0

	while [[ -n $current_folder_uid && $current_folder_uid != "null" && $current_depth -lt $max_depth ]]; do
		folder_details_json=$(get_folder_path_details "$current_folder_uid")

		# Extract title and parentUid using jq
		if ! title=$(echo "$folder_details_json" | jq -r '.title // empty'); then
			echo "ERROR: Failed to parse title from folder details: $folder_details_json" >&2
			break
		fi

		if ! parent_uid=$(echo "$folder_details_json" | jq -r '.parentUid // empty'); then
			echo "ERROR: Failed to parse parentUid from folder details: $folder_details_json" >&2
			break
		fi

		if [[ -z $title || $title == "null" ]]; then
			echo "WARNING: Encountered folder with no title (UID: $current_folder_uid). Path reconstruction may be incomplete." >&2
			break
		fi

		slug_title=$(slugify "$title")
		path_components=("$slug_title" "${path_components[@]}") # Prepend slugified title to build path in reverse (Child, Parent, Root)

		if [[ -z $parent_uid || $parent_uid == "null" ]]; then
			break
		fi

		current_folder_uid="$parent_uid"
		((current_depth++))
	done

	if [[ $current_depth -ge $max_depth ]]; then
		echo "WARNING: Reached max folder depth during path reconstruction for initial folder UID '$1'. Path might be truncated." >&2
	fi

	# Echo space-separated list of titles. Caller will capture into an array.
	# This order is Parent/Child because we prepended.
	echo "${path_components[*]}"
}

create_folder() {
	local folder_title=$1
	local new_folder_uid

	local json_payload
	json_payload=$(jq -cn --arg title "$folder_title" '{spec: {title: $title}}')

	new_folder_uid=$(curl --silent --fail --show-error -X POST \
		-H "Authorization: Bearer $GRAFANA_API_TOKEN" \
		-H "Content-Type: application/json" \
		-d "$json_payload" \
		"$URL/apis/folder.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/folders" |
		jq -r '.metadata.name // empty')

	echo "$new_folder_uid"
}

list_dashboards() {
	curl \
		--silent --fail --show-error \
		-H "Authorization: Bearer $GRAFANA_API_TOKEN" \
		"$URL/apis/dashboard.grafana.app/$API_VERSION/namespaces/$GRAFANA_ORG_NAMESPACE/dashboards" |
		jq -c '.items[]? | {uid: .metadata.name, title: .spec.title, folderUid: (.metadata.annotations."grafana.app/folder" // "")}'
}

main "$@"
