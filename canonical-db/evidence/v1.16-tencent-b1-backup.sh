#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/home/ubuntu/phoenix-canonical-db-deploy
cd "$root/deploy/tencent"
set -a
. ./.env
set +a
test "$PHOENIX_DB_NAME" = phoenix_canonical_dev
mkdir -p backups
chmod 700 backups
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump="backups/phoenix_canonical_preupgrade_v116_${stamp}.dump"
pgpass=/tmp/phoenix-v116-b1.pgpass
printf '%s\n' "*:*:*:phoenix_canonical_backup_runtime:$PHOENIX_DB_BACKUP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$pgpass'; chmod 600 '$pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres rm -f "$pgpass" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker compose --env-file .env exec -T -e "PGPASSFILE=$pgpass" postgres \
  pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_runtime -d "$PHOENIX_DB_NAME" -Fc </dev/null > "$dump"
chmod 600 "$dump"
digest="$(sha256sum "$dump" | awk '{print $1}')"
entries="$(docker compose --env-file .env exec -T postgres pg_restore --list "/backups/$(basename "$dump")" </dev/null | grep -c '^[0-9]*;' || true)"
test "$entries" -gt 0
printf '{"database":"%s","created_utc":"%s","sha256":"%s","format":"pg_custom","purpose":"preupgrade-v1.16"}\n' \
  "$PHOENIX_DB_NAME" "$stamp" "$digest" > "$dump.manifest.json"
printf '{"verified_utc":"%s","pg_restore_entries":%s}\n' "$stamp" "$entries" > "$dump.verified"
chmod 600 "$dump.manifest.json" "$dump.verified"
echo "BACKUP=$dump"
echo "SHA256=$digest"
echo "PG_RESTORE_ENTRIES=$entries"
echo "MODES=$(stat -c '%a,%a,%a' "$dump" "$dump.manifest.json" "$dump.verified")"
echo "RESULT=PASS_B1_BACKUP"
