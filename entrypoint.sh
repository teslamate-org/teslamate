#!/bin/sh
set -e

: "${DATABASE_HOST:="127.0.0.1"}"
: "${DATABASE_PORT:=5432}"

# wait until the postgres port opens
sleep 1s
p=1
while : ; do
  set +e
  if (nc -z ${DATABASE_HOST} ${DATABASE_PORT}) >/dev/null 2>&1; then set -e; break; fi
  set -e
  p=$((p + p))
  echo waiting for postgres at ${DATABASE_HOST}:${DATABASE_PORT} \("$p"sec\)
  sleep "${p}"s
done

# apply migrations
bin/teslamate eval "TeslaMate.Release.migrate"

exec "$@"
