#!/usr/bin/env dash
set -e

: "${DATABASE_HOST:="127.0.0.1"}"
: "${DATABASE_PORT:=5432}"
: "${ULIMIT_MAX_NOFILE:=65536}"

# prevent memory bloat in some misconfigured versions of Docker/containerd
# where the nofiles limit is very large. 0 means don't set it.
if test "${ULIMIT_MAX_NOFILE}" != 0 && test "$(ulimit -n)" -gt "${ULIMIT_MAX_NOFILE}"; then
	ulimit -n "${ULIMIT_MAX_NOFILE}"
fi

# wait until Postgres is ready
while ! nc -z "${DATABASE_HOST}" "${DATABASE_PORT}" 2>/dev/null; do
	echo waiting for postgres at "${DATABASE_HOST}":"${DATABASE_PORT}"
	sleep 1s
done

# apply migrations
bin/teslamate eval "TeslaMate.Release.migrate"

exec "$@"
