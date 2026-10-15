#!/usr/bin/env bash
set -euo pipefail
umask 077

printf '127.0.0.1:5432:*:phoenix_bootstrap:%s\n' "$POSTGRES_PASSWORD" > /tmp/f10-bootstrap.pgpass
chmod 600 /tmp/f10-bootstrap.pgpass
export PGPASSFILE=/tmp/f10-bootstrap.pgpass

psql_bootstrap() {
  psql -X -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}

for migration in /opt/migrations/000*.sql; do
  name="$(basename "$migration")"
  digest="$(sha256sum "$migration" | cut -d' ' -f1)"
  ledger_exists="$(psql_bootstrap -Atqc "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL")"
  if [ "$ledger_exists" = t ]; then
    existing="$(psql_bootstrap -Atqc "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name='$name'")"
    if [ -n "$existing" ]; then
      test "$existing" = "$digest" || { echo "DRIFT_REFUSED $name"; exit 1; }
      echo "SKIP $name checksum verified"
      continue
    fi
  fi
  sed '1{/^[[:space:]]*BEGIN;[[:space:]]*$/d;}; ${/^[[:space:]]*COMMIT;[[:space:]]*$/d;}' "$migration" > /tmp/f10-body.sql
  {
    echo 'BEGIN;'
    echo 'SELECT pg_advisory_xact_lock(2202,1);'
    cat /tmp/f10-body.sql
    echo "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$digest');"
    echo 'COMMIT;'
  } > /tmp/f10-atomic.sql
  psql_bootstrap -f /tmp/f10-atomic.sql >/tmp/f10-migration-output.txt || {
    cat /tmp/f10-migration-output.txt
    exit 1
  }
  echo "APPLIED $name $digest"
done

psql_bootstrap -Atqc "SELECT 'ledger='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity');"
