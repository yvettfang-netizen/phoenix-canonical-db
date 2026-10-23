#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/ubuntu/phoenix-canonical-db-deploy/deploy/tencent
set -a
. ./.env
set +a
pgpass=/tmp/phoenix-v116-preflight.pgpass
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$pgpass'; chmod 600 '$pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres rm -f "$pgpass" >/dev/null 2>&1 || true
  rm -f /home/ubuntu/.phoenix-v116-preflight.sql
}
trap cleanup EXIT
docker compose --env-file .env exec -T -e "PGPASSFILE=$pgpass" postgres \
  psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -f - \
  < /home/ubuntu/.phoenix-v116-preflight.sql
