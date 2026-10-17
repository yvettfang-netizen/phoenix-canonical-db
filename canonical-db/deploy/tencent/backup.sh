#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"
set -a
. ./.env
set +a
test "${PHOENIX_DB_BACKUP_PASSWORD:-}" != "" || { echo "missing backup credential" >&2; exit 1; }
mkdir -p backups
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump="backups/phoenix_canonical_${stamp}.dump"
test ! -e "$dump"
runtime_pgpass="/tmp/phoenix-backup.pgpass"
printf '%s\n' "*:*:*:phoenix_canonical_backup_runtime:$PHOENIX_DB_BACKUP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$runtime_pgpass'; chmod 600 '$runtime_pgpass'"
cleanup() { docker compose --env-file .env exec -T postgres sh -c "rm -f '$runtime_pgpass'" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker compose --env-file .env exec -T -e "PGPASSFILE=$runtime_pgpass" postgres \
  pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_runtime -d "$PHOENIX_DB_NAME" -Fc > "$dump"
digest="$(sha256sum "$dump" | awk '{print $1}')"
printf '{"database":"%s","created_utc":"%s","sha256":"%s","format":"pg_custom"}\n' "$PHOENIX_DB_NAME" "$stamp" "$digest" > "$dump.manifest.json"
# FD-7 rule 2: a backup counts only after pg_restore can read its table of contents. The marker file
# is separate so the manifest format that restore.sh checks stays unchanged.
entries="$(docker compose --env-file .env exec -T postgres pg_restore --list "/backups/$(basename "$dump")" | grep -c '^[0-9]*;' || true)"
[ "${entries:-0}" -gt 0 ] || { echo "backup verification failed: $dump" >&2; exit 1; }
printf '{"verified_utc":"%s","pg_restore_entries":%s}\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$entries" > "$dump.verified"
echo "BACKUP $dump"
echo "VERIFIED $dump entries=$entries"
