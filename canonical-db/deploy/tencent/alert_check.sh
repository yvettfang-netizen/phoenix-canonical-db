#!/usr/bin/env bash
# FD-7 rule 6: local alert check. Writes findings to alerts/alerts-<YYYYMMDD>.log and exits 1 when any
# alert is raised. It NEVER sends anything to an external channel; the delivery channel is registered
# later under incident gate G-5. Conditions:
#   BACKUP_STALE         no verified backup in the last 26 hours
#   BACKUP_FAILED        newest backup has no verification marker
#   RESTORE_DRILL_FAILED newest drill report is not RESULT=PASS (or none in 35 days)
#   DB_UNAVAILABLE       health.sh fails (database down or reader login broken)
#   LEDGER_MISMATCH      migration ledger differs from the migration files
#   DISK_USAGE           filesystem holding backups/ above 80 percent
#   AUDIT_CHAIN_BROKEN   audit_extract.sh --verify fails
#   RECONCILE_LOG_ONLY   decisions present only in the server log for the newest extracted day (lead)
set -uo pipefail
umask 077
cd "$(dirname "$0")"
mkdir -p alerts; chmod 700 alerts
out="alerts/alerts-$(date -u +%Y%m%d).log"; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; count=0
alert() { echo "$now ALERT $1 $2" | tee -a "$out"; count=$((count+1)); }
envval() { grep "^$1=" .env | cut -d= -f2-; }
dbname="$(envval PHOENIX_DB_NAME)"

mapfile -t runtime_backups < <(find backups -maxdepth 1 -type f -name 'phoenix_canonical_[0-9]*.dump' -printf '%T@ %p\n' 2>/dev/null |
  sort -nr | cut -d' ' -f2-)
newest="${runtime_backups[0]:-}"
newest_verified="$(for d in "${runtime_backups[@]}"; do [ -f "$d.verified" ] && { echo "$d"; break; }; done)"
if [ -z "$newest_verified" ]; then alert BACKUP_STALE "no verified backup"; else
  s="$(basename "$newest_verified" .dump)"; s="${s#phoenix_canonical_}"
  age_h=$(( ( $(date -u +%s) - $(date -u -d "${s:0:4}-${s:4:2}-${s:6:2}T${s:9:2}:${s:11:2}:${s:13:2}Z" +%s) ) / 3600 ))
  [ "$age_h" -gt 26 ] && alert BACKUP_STALE "newest verified backup is ${age_h}h old"
fi
[ -n "$newest" ] && [ ! -f "$newest.verified" ] && alert BACKUP_FAILED "newest backup $newest is not verified"

drill="$(ls drills/drill-*.txt 2>/dev/null | sort | tail -1)"
if [ -z "$drill" ]; then alert RESTORE_DRILL_FAILED "no restore drill report"; else
  grep -q '^RESULT=PASS$' "$drill" || alert RESTORE_DRILL_FAILED "$drill"
  [ -n "$(find "$drill" -mtime +35 2>/dev/null)" ] && alert RESTORE_DRILL_FAILED "newest drill older than 35 days"
fi

bash ./health.sh >/dev/null 2>&1 || alert DB_UNAVAILABLE "health.sh failed"

pw="$(envval PHOENIX_DB_READER_PASSWORD)"
printf '%s\n' "*:*:*:phoenix_canonical_reader_runtime:$pw" | docker compose --env-file .env exec -T postgres sh -c 'umask 077; cat > /tmp/phoenix-alert-reader.pgpass' 2>/dev/null
ledger="$(docker compose --env-file .env exec -T -e PGPASSFILE=/tmp/phoenix-alert-reader.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_reader_runtime -d "$dbname" -c "SELECT migration_name||' '||sha256 FROM canonical_migrations.applied ORDER BY migration_name" 2>/dev/null | tr -d '\r')"
docker compose --env-file .env exec -T postgres sh -c 'rm -f /tmp/phoenix-alert-reader.pgpass' >/dev/null 2>&1
files="$(for m in ../../migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql; do echo "$(basename "$m") $(sha256sum "$m" | awk '{print $1}')"; done)"
[ "$ledger" = "$files" ] || alert LEDGER_MISMATCH "ledger rows=$(grep -c . <<<"$ledger") files=$(grep -c . <<<"$files")"

use="$(df -P backups 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')"
[ -n "$use" ] && [ "$use" -gt 80 ] && alert DISK_USAGE "backups filesystem ${use}%"

if [ -s audit/chain.txt ]; then
  bash ./audit_extract.sh --verify >/dev/null 2>&1 || alert AUDIT_CHAIN_BROKEN "audit_extract.sh --verify failed"
  day="$(tail -n 1 audit/chain.txt | awk '{print $1}')"
  if [ -f "audit/$day.audit" ]; then
    bpw="$(envval PHOENIX_DB_BACKUP_PASSWORD)"
    printf '%s\n' "*:*:*:phoenix_canonical_backup_runtime:$bpw" | docker compose --env-file .env exec -T postgres sh -c 'umask 077; cat > /tmp/phoenix-alert-backup.pgpass' 2>/dev/null
    ids="$(docker compose --env-file .env exec -T -e PGPASSFILE=/tmp/phoenix-alert-backup.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_backup_runtime -d "$dbname" -c "SELECT attempt_id FROM audit.access_events WHERE attempt_id IS NOT NULL" 2>/dev/null | tr -d '\r' | sort -u)"
    docker compose --env-file .env exec -T postgres sh -c 'rm -f /tmp/phoenix-alert-backup.pgpass' >/dev/null 2>&1
    logonly="$(grep -oE 'attempt_id=[0-9a-f-]{36}' "audit/$day.audit" | cut -d= -f2 | sort -u | comm -23 - <(echo "$ids") | wc -l)"
    [ "$logonly" -gt 0 ] && alert RECONCILE_LOG_ONLY "$day: $logonly decision(s) only in the server log (rolled back); review"
  fi
fi
echo "$now ALERT_CHECK done alerts=$count" | tee -a "$out"
[ "$count" -eq 0 ]
