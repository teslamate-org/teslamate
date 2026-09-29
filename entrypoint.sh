#!/usr/bin/env dash
set -e

: "${ULIMIT_MAX_NOFILE:=65536}"

# prevent memory bloat in some misconfigured versions of Docker/containerd
# where the nofiles limit is very large. 0 means don't set it.
if test "${ULIMIT_MAX_NOFILE}" != 0 && test "$(ulimit -n)" -gt "${ULIMIT_MAX_NOFILE}"; then
	ulimit -n "${ULIMIT_MAX_NOFILE}"
fi

# wait until the database accepts connections, then apply migrations
bin/teslamate eval "TeslaMate.Release.wait_for_database_and_migrate()"

exec "$@"
