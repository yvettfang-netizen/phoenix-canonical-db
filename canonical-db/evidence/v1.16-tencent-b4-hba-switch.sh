#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/ubuntu/phoenix-canonical-db-deploy/deploy/tencent
set -a
. ./.env
set +a
bootstrap_pgpass=/tmp/phoenix-v116-b4-bootstrap.pgpass
runtime_pgpass=/tmp/phoenix-v116-b4-runtime.pgpass
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"
{
  printf '%s\n' "*:*:*:phoenix_canonical_reader_runtime:$PHOENIX_DB_READER_PASSWORD"
  printf '%s\n' "*:*:*:phoenix_canonical_backup_runtime:$PHOENIX_DB_BACKUP_PASSWORD"
  printf '%s\n' "*:*:*:phoenix_canonical_binder_runtime:$PHOENIX_DB_BINDER_PASSWORD"
} | docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$runtime_pgpass'; chmod 600 '$runtime_pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres rm -f "$bootstrap_pgpass" "$runtime_pgpass" >/dev/null 2>&1 || true
}
trap cleanup EXIT
q() {
  docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
    psql -X -Atq -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@" </dev/null
}
hba="$(q -c 'SHOW hba_file;')"
[[ "$hba" == /var/lib/postgresql/data/* ]]
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="${hba}.codex-v116-${stamp}.bak"
before_sha="$(docker compose --env-file .env exec -T postgres sha256sum "$hba" </dev/null | awk '{print $1}')"
trust_before="$(docker compose --env-file .env exec -T postgres sh -c "grep -Ec '^[[:space:]]*local[[:space:]]+.*[[:space:]]+trust([[:space:]]|$)' '$hba'" </dev/null)"
test "$trust_before" -eq 2
docker compose --env-file .env exec -T postgres sh -c "cp '$hba' '$backup'; chmod 600 '$backup'; sed -E -i 's/^([[:space:]]*local[[:space:]]+.*[[:space:]]+)trust([[:space:]]*(#.*)?)$/\\1scram-sha-256\\2/' '$hba'" </dev/null
rollback() {
  echo "ROLLBACK restoring $backup"
  docker compose --env-file .env exec -T postgres cp "$backup" "$hba" </dev/null || true
  q -c 'SELECT pg_reload_conf();' >/dev/null || true
}
trap rollback ERR
after_sha="$(docker compose --env-file .env exec -T postgres sha256sum "$hba" </dev/null | awk '{print $1}')"
test "$after_sha" != "$before_sha"
test "$(q -c 'SELECT pg_reload_conf();')" = t
test "$(q -c "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;")" = 0
test "$(q -c "SELECT count(*) FROM pg_hba_file_rules WHERE auth_method='trust';")" = 0

trap - ERR
set +e
no_password="$(docker compose --env-file .env exec -T postgres sh -c "unset PGPASSWORD PGPASSFILE; psql -X -Atq -U phoenix_bootstrap -d '$PHOENIX_DB_NAME' -c 'SELECT 1;'" </dev/null 2>&1)"
no_password_rc=$?
set -e
trap rollback ERR
test "$no_password_rc" -ne 0
grep -Eq 'no password supplied|password authentication failed' <<<"$no_password"

for role in phoenix_canonical_reader_runtime phoenix_canonical_backup_runtime phoenix_canonical_binder_runtime; do
  got="$(docker compose --env-file .env exec -T -e "PGPASSFILE=$runtime_pgpass" postgres \
    psql -X -Atq -U "$role" -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -c 'SELECT current_user;' </dev/null)"
  test "$got" = "$role"
  echo "socket_auth_$role=PASS"
done
trap - ERR
echo "hba_backup=$backup"
echo "hba_before_sha256=$before_sha"
echo "hba_after_sha256=$after_sha"
echo "trust_rules_before=$trust_before"
echo "trust_rules_after=0"
echo "socket_without_password=REFUSED"
echo "pg_hba_rules:"
q -c "SELECT type||'|'||coalesce(database::text,'')||'|'||coalesce(user_name::text,'')||'|'||coalesce(address,'')||'|'||auth_method FROM pg_hba_file_rules ORDER BY line_number;"
echo "RESULT=PASS_B4_HBA_SWITCH"
