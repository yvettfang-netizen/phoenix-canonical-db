#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
. ./.env
set +a
test "${PHOENIX_DB_READER_PASSWORD:-}" != "" || { echo "missing reader credential" >&2; exit 1; }
runtime_pgpass="/tmp/phoenix-health-reader.pgpass"
printf '%s\n' "*:*:*:phoenix_canonical_reader_runtime:$PHOENIX_DB_READER_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$runtime_pgpass'; chmod 600 '$runtime_pgpass'"
cleanup() { docker compose --env-file .env exec -T postgres sh -c "rm -f '$runtime_pgpass'" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker compose --env-file .env exec -T -e "PGPASSFILE=$runtime_pgpass" postgres pg_isready -h 127.0.0.1 -U phoenix_canonical_reader_runtime -d "$PHOENIX_DB_NAME"
docker compose --env-file .env exec -T -e "PGPASSFILE=$runtime_pgpass" postgres \
  psql -X -h 127.0.0.1 -U phoenix_canonical_reader_runtime -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -Atqc \
  "SELECT 'version='||current_setting('server_version'); SELECT 'migrations='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning');"
