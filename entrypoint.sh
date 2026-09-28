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

# wait until Postgres is ready. With DATABASE_SOCKET_DIR set, TeslaMate
# connects to the Unix socket <dir>/.s.PGSQL.<port> and ignores DATABASE_HOST,
# so wait for that socket instead
if test "${DATABASE_SOCKET_DIR+set}" = set; then
	if test -z "${DATABASE_SOCKET_DIR}"; then
		echo "DATABASE_SOCKET_DIR is empty: set it to the directory of the Postgres socket, or unset it to connect to DATABASE_HOST" >&2
		exit 1
	fi
	socket="${DATABASE_SOCKET_DIR}/.s.PGSQL.${DATABASE_PORT}"
	while ! error=$(nc -zU "${socket}" 2>&1); do
		echo waiting for postgres at "${socket}" "(${error##*: })"
		sleep 1s
	done
else
	while ! nc -z "${DATABASE_HOST}" "${DATABASE_PORT}" 2>/dev/null; do
		echo waiting for postgres at "${DATABASE_HOST}":"${DATABASE_PORT}"
		sleep 1s
	done
fi

# apply migrations
bin/teslamate eval "TeslaMate.Release.migrate"

exec "$@"
