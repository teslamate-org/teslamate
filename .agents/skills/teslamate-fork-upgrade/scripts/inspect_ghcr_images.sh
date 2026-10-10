#!/usr/bin/env bash
# Inspect the fork's GHCR images anonymously: index digest, per-platform
# manifest digests, and the OCI version/revision labels of the amd64 image.
# Anonymous access proves the packages are public.
#
# Usage: bash inspect_ghcr_images.sh [tag]   (default tag: main)
set -euo pipefail

tag="${1:-main}"
index_types='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json'
manifest_types='application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

for repo in rewse/teslamate rewse/teslamate/grafana; do
	token=$(curl -fsS "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)
	auth="Authorization: Bearer ${token}"
	url="https://ghcr.io/v2/${repo}/manifests/${tag}"
	digest=$(curl -fsSI -H "$auth" -H "Accept: ${index_types}" "$url" |
		tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
	index=$(curl -fsS -H "$auth" -H "Accept: ${index_types}" "$url")
	amd64=$(jq -r '.manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest' <<<"$index")
	config=$(curl -fsS -H "$auth" -H "Accept: ${manifest_types}" "https://ghcr.io/v2/${repo}/manifests/${amd64}" | jq -r .config.digest)
	labels=$(curl -fsSL -H "$auth" "https://ghcr.io/v2/${repo}/blobs/${config}" |
		jq -c '.config.Labels | {version: .["org.opencontainers.image.version"], revision: .["org.opencontainers.image.revision"]}')
	jq -n --arg repo "$repo" --arg tag "$tag" --arg index "$digest" --argjson labels "$labels" --argjson platforms \
		"$(jq -c '[.manifests[] | select(.platform.os != "unknown") | {platform: "\(.platform.os)/\(.platform.architecture)", digest}]' <<<"$index")" \
		'{repo: $repo, ref: "ghcr.io/\($repo):\($tag)@\($index)", platforms: $platforms, labels: $labels}'
done
