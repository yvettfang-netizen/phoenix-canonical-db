#!/usr/bin/env bash
set -euo pipefail
umask 077

printf '127.0.0.1:5432:*:phoenix_bootstrap:%s\n' "$POSTGRES_PASSWORD" > /tmp/f10-restore-bootstrap.pgpass
chmod 600 /tmp/f10-restore-bootstrap.pgpass
export PGPASSFILE=/tmp/f10-restore-bootstrap.pgpass

psql_restore() {
  psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}

test "$(sha256sum /f10backup/source.dump | cut -d' ' -f1)" = "$(cat /f10backup/source.dump.sha256)" || {
  echo 'RESTORE_MANIFEST_DIGEST_MISMATCH'
  exit 1
}
test "$(psql_restore -Atqc "SELECT to_regclass('canonical_migrations.applied') IS NULL")" = t

psql_restore <<'SQL'
CREATE ROLE phoenix_canonical_migrator NOLOGIN NOINHERIT;
CREATE ROLE phoenix_canonical_app NOLOGIN NOINHERIT;
CREATE ROLE phoenix_canonical_reader NOLOGIN NOINHERIT;
CREATE ROLE phoenix_canonical_context_binder NOLOGIN NOINHERIT;
CREATE ROLE phoenix_canonical_backup_runtime NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
CREATE ROLE phoenix_canonical_app_f10 NOLOGIN;
CREATE ROLE phoenix_canonical_binder_f10 NOLOGIN;
CREATE ROLE phoenix_canonical_backup_f10 NOLOGIN;
SQL

pg_restore -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev \
  --no-owner --exit-on-error /f10backup/source.dump

catalog="$(psql_restore -Atqc "SELECT 'ledger='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity'); SELECT 'people='||count(*) FROM core.people;")"
printf '%s\n' "$catalog"
grep -qx 'ledger=15' <<<"$catalog"
grep -qx 'tables=26' <<<"$catalog"
grep -qx 'policies=20' <<<"$catalog"
grep -q '^people=[1-9]' <<<"$catalog"

for suite in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql f10_catalog_regression.sql f10_d6_immutability_regression.sql f10_v16_document_trigger.sql; do
  psql_restore -f "/opt/tests/$suite" >/tmp/f10-restore-suite.log
  echo "PASS restored $suite"
done
echo 'PASS fresh-cluster manifest-verified restore with synthetic rows and 0015'
