#!/bin/sh
set -e

: ${DATABASE_HOST:='127.0.0.1'}

# wait until the postgres port opens
sleep 1s
p=1
while : ; do
  set +e
  (nc -z ${DATABASE_HOST} 5432) >/dev/null 2>&1
  [[ $? -eq 0 ]] && break
  set -e
  p=`expr $p + $p`
  echo waiting for postgres at ${DATABASE_HOST} \(${p}sec\)
  sleep ${p}s
done

# apply migrations
bin/teslamate eval "TeslaMate.Release.migrate"

exec "$@"
