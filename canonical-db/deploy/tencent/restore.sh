#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"

test -f .env || { echo "missing deploy/tencent/.env" >&2; exit 1; }
set -a
. ./.env
set +a

test "${PHOENIX_DB_NAME:-}" = "phoenix_canonical_dev" || { echo "unexpected database name" >&2; exit 1; }
for name in PHOENIX_DB_BOOTSTRAP_PASSWORD PHOENIX_DB_READER_PASSWORD PHOENIX_DB_APP_PASSWORD PHOENIX_DB_BINDER_PASSWORD PHOENIX_DB_MIGRATOR_PASSWORD PHOENIX_DB_BACKUP_PASSWORD; do
  value="${!name:-}"
  [[ "$value" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid or missing $name" >&2; exit 1; }
done

backup="${1:-}"
test -n "$backup" || { echo "usage: restore.sh backups/<dump>.dump" >&2; exit 1; }
case "$backup" in
  backups/phoenix_canonical_*.dump) ;;
  *) echo "restore source must be an approved local backups/ dump" >&2; exit 1 ;;
esac
test -f "$backup" || { echo "backup not found" >&2; exit 1; }
manifest="$backup.manifest.json"
test -f "$manifest" || { echo "backup manifest not found" >&2; exit 1; }
# The manifest is the single-line JSON written by backup.sh; parse it without a host interpreter and
# accept only that exact shape.
manifest_line="$(cat "$manifest")"
[[ "$manifest_line" =~ ^\{\"database\":\"phoenix_canonical_dev\",\"created_utc\":\"[0-9]{8}T[0-9]{6}Z\",\"sha256\":\"([0-9a-f]{64})\",\"format\":\"pg_custom\"\}$ ]] \
  || { echo "invalid backup manifest" >&2; exit 1; }
expected="${BASH_REMATCH[1]}"
actual="$(sha256sum "$backup" | awk '{print $1}')"
test "$expected" = "$actual" || { echo "backup manifest digest mismatch" >&2; exit 1; }

docker compose --env-file .env up -d --wait postgres
bootstrap_pgpass="/tmp/phoenix-restore-bootstrap.pgpass"
runtime_sql="/tmp/phoenix-restore-roles.sql"
container_dump="/tmp/phoenix-restore.dump"
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres sh -c "rm -f '$bootstrap_pgpass' '$runtime_sql' '$container_dump'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql_exec() {
  docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
    psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}

existing="$(psql_exec -Atqc "SELECT CASE WHEN to_regclass('canonical_migrations.applied') IS NULL THEN 'empty' ELSE 'nonempty' END;")"
test "$existing" = "empty" || { echo "restore target is not a fresh Canonical database" >&2; exit 1; }

cat > "$runtime_sql" <<SQL
-- Role statements carry password literals: keep them and their error context out of the server log.
SET log_min_messages = panic;
SET log_min_error_statement = panic;
DO \$roles\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_migrator') THEN CREATE ROLE phoenix_canonical_migrator NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_app') THEN CREATE ROLE phoenix_canonical_app NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_reader') THEN CREATE ROLE phoenix_canonical_reader NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_context_binder') THEN CREATE ROLE phoenix_canonical_context_binder NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_migrator_runtime') THEN CREATE ROLE phoenix_canonical_migrator_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_MIGRATOR_PASSWORD'; ELSE ALTER ROLE phoenix_canonical_migrator_runtime PASSWORD '$PHOENIX_DB_MIGRATOR_PASSWORD'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_app_runtime') THEN CREATE ROLE phoenix_canonical_app_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_APP_PASSWORD'; ELSE ALTER ROLE phoenix_canonical_app_runtime PASSWORD '$PHOENIX_DB_APP_PASSWORD'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_reader_runtime') THEN CREATE ROLE phoenix_canonical_reader_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_READER_PASSWORD'; ELSE ALTER ROLE phoenix_canonical_reader_runtime PASSWORD '$PHOENIX_DB_READER_PASSWORD'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_binder_runtime') THEN CREATE ROLE phoenix_canonical_binder_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_BINDER_PASSWORD'; ELSE ALTER ROLE phoenix_canonical_binder_runtime PASSWORD '$PHOENIX_DB_BINDER_PASSWORD'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_backup_runtime') THEN CREATE ROLE phoenix_canonical_backup_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$PHOENIX_DB_BACKUP_PASSWORD'; ELSE ALTER ROLE phoenix_canonical_backup_runtime LOGIN BYPASSRLS PASSWORD '$PHOENIX_DB_BACKUP_PASSWORD'; END IF;
END
\$roles\$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_runtime WITH INHERIT TRUE, SET FALSE;
GRANT pg_read_all_data TO phoenix_canonical_backup_runtime WITH INHERIT TRUE, SET FALSE;
GRANT CONNECT ON DATABASE "$PHOENIX_DB_NAME" TO phoenix_canonical_backup_runtime;
SQL
cat "$runtime_sql" | docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
  psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -f -

docker compose --env-file .env cp "$backup" "postgres:$container_dump"
docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
  pg_restore -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" --no-owner --exit-on-error "$container_dump"

psql_exec -Atqc "SELECT 'ledger='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT 'backup_role='||rolsuper||':'||rolbypassrls FROM pg_roles WHERE rolname='phoenix_canonical_backup_runtime';"
echo "PASS fresh-cluster restore with role bootstrap and manifest verification"
