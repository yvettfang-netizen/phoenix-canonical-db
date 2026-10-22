#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"

test -f .env || { echo "missing deploy/tencent/.env" >&2; exit 1; }
set -a
. ./.env
set +a

test "${PHOENIX_DB_NAME:-}" = "phoenix_canonical_dev" || { echo "unexpected database name" >&2; exit 1; }
for name in PHOENIX_DB_BOOTSTRAP_PASSWORD PHOENIX_DB_MIGRATOR_PASSWORD PHOENIX_DB_APP_PASSWORD PHOENIX_DB_READER_PASSWORD PHOENIX_DB_BINDER_PASSWORD PHOENIX_DB_BACKUP_PASSWORD; do
  value="${!name:-}"
  [[ "$value" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid or missing $name" >&2; exit 1; }
done
command -v docker >/dev/null
docker compose version >/dev/null
mkdir -p backups
chmod 700 backups

docker compose --env-file .env up -d --wait postgres

bootstrap_pgpass="/tmp/phoenix-bootstrap.pgpass"
runtime_pgpass="/tmp/phoenix-runtime.pgpass"
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"
cleanup_pgpass() {
  docker compose --env-file .env exec -T postgres sh -c "rm -f '$bootstrap_pgpass' '$runtime_pgpass'" >/dev/null 2>&1 || true
}
trap cleanup_pgpass EXIT

psql_exec() {
  docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
    psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}

for migration in ../../migrations/canonical/*.sql; do
  name="$(basename "$migration")"
  [[ "$name" =~ ^[0-9]{4}_[a-z0-9_]+\.sql$ ]] || { echo "invalid migration name: $name" >&2; exit 1; }
  digest="$(sha256sum "$migration" | awk '{print $1}')"
  ledger_exists="$(psql_exec -Atqc "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;")"
  existing=""
  if [ "$ledger_exists" = "t" ]; then
    existing="$(psql_exec -Atqc "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name='$name';")"
  fi
  if [ -n "$existing" ]; then
    [ "$existing" = "$digest" ] || { echo "migration checksum changed: $name" >&2; exit 1; }
    echo "SKIP $name checksum verified"
    continue
  fi

  first="$(awk 'NF { print; exit }' "$migration")"
  last="$(awk 'NF { line=$0 } END { print line }' "$migration")"
  [ "$first" = "BEGIN;" ] && [ "$last" = "COMMIT;" ] || { echo "migration wrapper invalid: $name" >&2; exit 1; }
  nested="$(sed '1{/^[[:space:]]*BEGIN;[[:space:]]*$/d;}; ${/^[[:space:]]*COMMIT;[[:space:]]*$/d;}' "$migration" | grep -E '^[[:space:]]*(BEGIN|COMMIT|ROLLBACK)[[:space:]]*;' || true)"
  [ -z "$nested" ] || { echo "nested transaction command in migration: $name" >&2; exit 1; }
  atomic="$(mktemp)"
  {
    echo "BEGIN;"
    echo "SELECT pg_advisory_xact_lock(2202,1);"
    if [ "$ledger_exists" = "t" ]; then
      echo "DO \$guard\$ BEGIN IF EXISTS (SELECT 1 FROM canonical_migrations.applied WHERE migration_name='$name') THEN RAISE EXCEPTION 'migration registered while waiting for lock: $name'; END IF; END \$guard\$;"
    fi
    sed '1{/^[[:space:]]*BEGIN;[[:space:]]*$/d;}; ${/^[[:space:]]*COMMIT;[[:space:]]*$/d;}' "$migration"
    echo "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$digest');"
    echo "COMMIT;"
  } > "$atomic"
  psql_exec -f - < "$atomic"
  rm -f "$atomic"
  echo "APPLIED $name"
done

sql="$(mktemp)"
cat > "$sql" <<SQL
-- Role statements carry password literals: keep them and their error context out of the server log.
SET log_min_messages = panic;
SET log_min_error_statement = panic;
DO \$roles\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_migrator_runtime') THEN
    CREATE ROLE phoenix_canonical_migrator_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_MIGRATOR_PASSWORD';
  ELSE
    ALTER ROLE phoenix_canonical_migrator_runtime PASSWORD '$PHOENIX_DB_MIGRATOR_PASSWORD';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_app_runtime') THEN
    CREATE ROLE phoenix_canonical_app_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_APP_PASSWORD';
  ELSE
    ALTER ROLE phoenix_canonical_app_runtime PASSWORD '$PHOENIX_DB_APP_PASSWORD';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_reader_runtime') THEN
    CREATE ROLE phoenix_canonical_reader_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_READER_PASSWORD';
  ELSE
    ALTER ROLE phoenix_canonical_reader_runtime PASSWORD '$PHOENIX_DB_READER_PASSWORD';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_binder_runtime') THEN
    CREATE ROLE phoenix_canonical_binder_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$PHOENIX_DB_BINDER_PASSWORD';
  ELSE
    ALTER ROLE phoenix_canonical_binder_runtime PASSWORD '$PHOENIX_DB_BINDER_PASSWORD';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_backup_runtime') THEN
    CREATE ROLE phoenix_canonical_backup_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$PHOENIX_DB_BACKUP_PASSWORD';
  ELSE
    ALTER ROLE phoenix_canonical_backup_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$PHOENIX_DB_BACKUP_PASSWORD';
  END IF;
END
\$roles\$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_runtime WITH INHERIT TRUE, SET FALSE;
GRANT pg_read_all_data TO phoenix_canonical_backup_runtime WITH INHERIT TRUE, SET FALSE;
GRANT CONNECT ON DATABASE "$PHOENIX_DB_NAME" TO phoenix_canonical_backup_runtime;
SQL
psql_exec -f - < "$sql"
rm -f "$sql"

# D-10: the management SERVICE principal is created only by the installer. The ID (UUIDv7) and the
# label are not secrets; both must be set together. Without them, no family can be created through
# the API, so the install reports it instead of failing.
service_id="${PHOENIX_DB_SERVICE_PRINCIPAL_ID:-}"
service_label="${PHOENIX_DB_SERVICE_PRINCIPAL_LABEL:-}"
if [ -n "$service_id" ] || [ -n "$service_label" ]; then
  [[ "$service_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || { echo "PHOENIX_DB_SERVICE_PRINCIPAL_ID must be a lowercase UUIDv7" >&2; exit 1; }
  [[ "$service_label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$ ]] || { echo "PHOENIX_DB_SERVICE_PRINCIPAL_LABEL must be 1-200 characters from A-Z a-z 0-9 . _ - (no spaces: .env is sourced by bash)" >&2; exit 1; }
  existing_service="$(psql_exec -Atqc "SELECT principal_kind||':'||status FROM auth.principals WHERE principal_id='$service_id';")"
  if [ -z "$existing_service" ]; then
    [ "$(psql_exec -Atqc "SELECT auth.install_service_principal('$service_id','$service_label');")" = "t" ] || { echo "service principal install denied" >&2; exit 1; }
    echo "INSTALLED service principal $service_id"
  elif [ "$existing_service" = "SERVICE:ACTIVE" ]; then
    echo "SKIP service principal $service_id already active"
  else
    echo "service principal ID in use by $existing_service" >&2; exit 1
  fi
else
  echo "NOTE no PHOENIX_DB_SERVICE_PRINCIPAL_ID set: no management SERVICE principal installed"
fi

psql_exec -Atqc "SELECT current_database(); SELECT count(*) FROM canonical_migrations.applied; SELECT count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning');"
echo "PASS Phoenix Canonical PostgreSQL install"
