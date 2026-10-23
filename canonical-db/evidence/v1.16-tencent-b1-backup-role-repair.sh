#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/ubuntu/phoenix-canonical-db-deploy/deploy/tencent
set -a
. ./.env
set +a
bootstrap_pgpass=/tmp/phoenix-v116-bootstrap.pgpass
sql=/tmp/phoenix-v116-backup-role.sql
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres rm -f "$bootstrap_pgpass" "$sql" >/dev/null 2>&1 || true
}
trap cleanup EXIT
{
  echo "SET log_statement = 'none';"
  echo "SET log_min_messages = panic;"
  echo "SET log_min_error_statement = panic;"
  echo "ALTER ROLE phoenix_canonical_backup_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$PHOENIX_DB_BACKUP_PASSWORD';"
} | docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$sql'; chmod 600 '$sql'"
docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
  psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -f "$sql" </dev/null
test "$(docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres psql -X -Atq -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -c "SELECT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND rolbypassrls FROM pg_roles WHERE rolname='phoenix_canonical_backup_runtime';" </dev/null)" = t
echo "RESULT=PASS_BACKUP_ROLE_CREDENTIAL_REPAIRED"
