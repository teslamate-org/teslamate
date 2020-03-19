#!/bin/bash

set -o errexit

main() {
  local task=$1
  local version=$2

  if ! [[ "$task" =~ ^(build|push)$ ]]; then
    echo "ERROR: The task must be one of [build|push]."
    exit 1
  fi

  if [[ -z "$version" ]]; then
    echo "ERROR: A version must be specified.";
    exit 1
  fi

  grafana_dir=grafana

  pushd "$grafana_dir" > /dev/null || (echo "Couldn't change to $grafana_dir" && exit 1)
  build "$task" "teslamate/grafana:$version" linux/amd64,linux/arm64,linux/arm
  popd > /dev/null

  build "$task" "teslamate/teslamate:$version" linux/amd64,linux/arm64,linux/arm,linux/s390x,linux/386
  echo "Done"

}

build() {
  local task=$1
  local tag=$2
  local platforms=$3

  case $task in
      build) echo "Building $tag" && docker buildx build --pull --platform "$platforms" -t "$tag" .;;
      push)  echo "Pushing $tag" && docker buildx build --pull --platform "$platforms" -t "$tag" --push .;;
      *)     exit 1;;
  esac
}

main "$@"
