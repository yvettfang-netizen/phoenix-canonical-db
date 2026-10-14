#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
. ./.env
set +a
docker compose --env-file .env exec -T postgres pg_isready -U phoenix_bootstrap -d "$PHOENIX_DB_NAME"
docker compose --env-file .env exec -T postgres \
  env PGPASSWORD="$PHOENIX_DB_BOOTSTRAP_PASSWORD" \
  psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -Atqc \
  "SELECT 'version='||current_setting('server_version'); SELECT 'migrations='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity');"
