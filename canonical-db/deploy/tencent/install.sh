#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"

test -f .env || { echo "missing deploy/tencent/.env" >&2; exit 1; }
set -a
. ./.env
set +a

test "${PHOENIX_DB_NAME:-}" = "phoenix_canonical_dev" || { echo "unexpected database name" >&2; exit 1; }
for name in PHOENIX_DB_BOOTSTRAP_PASSWORD PHOENIX_DB_MIGRATOR_PASSWORD PHOENIX_DB_APP_PASSWORD PHOENIX_DB_READER_PASSWORD PHOENIX_DB_BINDER_PASSWORD; do
  value="${!name:-}"
  [[ "$value" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid or missing $name" >&2; exit 1; }
done
command -v docker >/dev/null
docker compose version >/dev/null
mkdir -p backups
chmod 700 backups

docker compose --env-file .env up -d --wait postgres

psql_exec() {
  docker compose --env-file .env exec -T postgres \
    env PGPASSWORD="$PHOENIX_DB_BOOTSTRAP_PASSWORD" \
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
END
\$roles\$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_runtime WITH INHERIT TRUE, SET FALSE;
SQL
psql_exec -f - < "$sql"
rm -f "$sql"

psql_exec -Atqc "SELECT current_database(); SELECT count(*) FROM canonical_migrations.applied; SELECT count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity'); SELECT count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity');"
echo "PASS Phoenix Canonical PostgreSQL install"
