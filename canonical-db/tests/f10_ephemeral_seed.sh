#!/usr/bin/env bash
set -euo pipefail
umask 077
export PGPASSFILE=/tmp/f10-bootstrap.pgpass

# Bootstrap creates database LOGIN roles and the installer SERVICE principal.
# Every synthetic business row below is made through the app's controlled API.
app_secret="$(openssl rand -hex 32)"
binder_secret="$(openssl rand -hex 32)"
backup_secret="$(openssl rand -hex 32)"
printf '127.0.0.1:5432:*:phoenix_canonical_app_f10:%s\n' "$app_secret" > /tmp/f10-app.pgpass
printf '127.0.0.1:5432:*:phoenix_canonical_binder_f10:%s\n' "$binder_secret" > /tmp/f10-binder.pgpass
printf '127.0.0.1:5432:*:phoenix_canonical_backup_f10:%s\n' "$backup_secret" > /tmp/f10-backup.pgpass
chmod 600 /tmp/f10-app.pgpass /tmp/f10-binder.pgpass /tmp/f10-backup.pgpass
psql -q -X -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE phoenix_canonical_app_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$app_secret';
CREATE ROLE phoenix_canonical_binder_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$binder_secret';
CREATE ROLE phoenix_canonical_backup_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$backup_secret';
GRANT phoenix_canonical_app TO phoenix_canonical_app_f10 WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_f10 WITH INHERIT TRUE, SET FALSE;
GRANT pg_read_all_data TO phoenix_canonical_backup_f10 WITH INHERIT TRUE, SET FALSE;
GRANT CONNECT ON DATABASE phoenix_canonical_dev TO phoenix_canonical_app_f10,phoenix_canonical_binder_f10,phoenix_canonical_backup_f10;
SQL
unset app_secret binder_secret backup_secret
test "$(psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT auth.install_service_principal('018f0000-0000-7000-8000-000000002001','Synthetic management service')")" = t
test "$(psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT auth.install_service_principal('018f0000-0000-7000-8000-000000002009','operations_entitlement_service')")" = t

app_psql() { PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
run_seed() {
  local family="$1" file="$2" ticket family_sql
  family_sql=NULL
  if [ "$family" != NULL ]; then family_sql="'$family'::uuid"; fi
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('018f0000-0000-7000-8000-000000002001',NULL,$family_sql,'INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'018f0000-0000-7000-8000-000000002001')")"
  {
    printf "SELECT auth.redeem_context_ticket('%s','018f0000-0000-7000-8000-000000002001');\n" "$ticket"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql -f -
}

run_seed NULL /opt/tests/f10_seed_unbound.sql
run_seed '018f0000-0000-7000-8000-000000000001' /opt/tests/f10_seed_family_a.sql
run_seed '018f0000-0000-7000-8000-000000000002' /opt/tests/f10_seed_family_b.sql
echo 'PASS API-seeded synthetic SERVICE(no person) families=2 guardian_authorities=2 assignments=4 operations_service=1'
