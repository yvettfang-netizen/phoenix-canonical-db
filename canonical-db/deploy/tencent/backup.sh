#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"
set -a
. ./.env
set +a
mkdir -p backups
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump="backups/phoenix_canonical_${stamp}.dump"
container_dump="/backups/$(basename "$dump")"
test ! -e "$dump"
docker compose --env-file .env exec -T postgres \
  env PGPASSWORD="$PHOENIX_DB_BOOTSTRAP_PASSWORD" \
  pg_dump -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -Fc -f "$container_dump"
digest="$(sha256sum "$dump" | awk '{print $1}')"
printf '{"database":"%s","created_utc":"%s","sha256":"%s","format":"pg_custom"}\n' "$PHOENIX_DB_NAME" "$stamp" "$digest" > "$dump.manifest.json"
echo "BACKUP $dump"
