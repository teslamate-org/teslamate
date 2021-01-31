#!/usr/bin/env sh
set -e

: "${DATABASE_HOST:="127.0.0.1"}"
: "${DATABASE_PORT:=5432}"

# wait until Postgres is ready
while ! nc -z ${DATABASE_HOST} ${DATABASE_PORT} 2>/dev/null; do
  echo waiting for postgres at ${DATABASE_HOST}:${DATABASE_PORT}
  sleep 1s
done

# apply migrations
bin/teslamate eval "TeslaMate.Release.migrate"

exec "$@"
