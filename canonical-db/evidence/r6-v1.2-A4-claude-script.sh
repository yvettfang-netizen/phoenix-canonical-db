#!/usr/bin/env bash
# Task A completion (R-6): bring the rebuilt local dev database to 0001-0009 with local roles and run the
# acceptance suites. Bash equivalent of db.ps1 init/provision-local-roles/probe (pwsh is not installed here).
# Secrets are read from the ignored local files and travel only through pipes; nothing secret is printed or
# placed on a command line.
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="$1"                                   # 16 | 17
ROOT="D:/CODEX/01_PHOENIX/01_NOVA/_worktrees/canonical-postgresql-phase1/canonical-db"
SVC="pg$V"; DB="phoenix_canonical_dev"; PGPASS="/tmp/phoenix-canonical-db.pgpass"
DC=(docker compose --env-file "$ROOT/.env" -f "$ROOT/compose.yaml")
[ "$V" = "17" ] && DC+=(--profile compat)
step() { echo; echo "### $*"; }
qb() { "${DC[@]}" exec -T -e "PGPASSFILE=$PGPASS" "$SVC" psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 -Atq "$@"; }
qu() { local u="$1"; shift; "${DC[@]}" exec -T -e "PGPASSFILE=$PGPASS" "$SVC" psql -X -h 127.0.0.1 -U "$u" -d "$DB" -v ON_ERROR_STOP=1 -Atq "$@"; }

echo "TASK A completion by Claude, $(date '+%F %T %z'), PostgreSQL $V, service $SVC, database $DB"
echo "Method: bash equivalent of db.ps1 (pwsh unavailable on this host). No secret value is printed."

step "A2b start service (existing exact volume phoenix-canonical-foundation_${SVC}_data; created if absent)"
"${DC[@]}" up -d --wait "$SVC" 2>&1 | tail -3
docker volume ls --format '{{.Name}}' | grep -E "^phoenix-canonical-foundation_${SVC}_data$"

step "A2c install container-local pgpass (bootstrap + five local roles) via stdin"
{ awk '/^PHOENIX_DB_BOOTSTRAP_PASSWORD=/{sub(/^[^=]*=/,""); print "*:*:*:phoenix_bootstrap:" $0}' "$ROOT/.env"
  awk -F= '/^PHOENIX_LOCAL_MIGRATOR_PASSWORD=/{print "*:*:*:phoenix_canonical_migrator_local:" $2}
           /^PHOENIX_LOCAL_APP_PASSWORD=/{print "*:*:*:phoenix_canonical_app_local:" $2}
           /^PHOENIX_LOCAL_READER_PASSWORD=/{print "*:*:*:phoenix_canonical_reader_local:" $2}
           /^PHOENIX_LOCAL_BINDER_PASSWORD=/{print "*:*:*:phoenix_canonical_context_binder_local:" $2}
           /^PHOENIX_LOCAL_BACKUP_PASSWORD=/{print "*:*:*:phoenix_canonical_backup_local:" $2}' "$ROOT/.local-roles.env"; } |
  "${DC[@]}" exec -T "$SVC" sh -c "umask 077; cat > '$PGPASS'; chmod 600 '$PGPASS'; wc -l < '$PGPASS' | sed 's/^/pgpass_entries=/'"

step "A2d bootstrap connection over host SCRAM"
qb -c "SELECT 'server_version='||current_setting('server_version')||' user='||current_user;" || { echo "STOP bootstrap auth failed"; exit 2; }
step "A3a local socket without pgpass must be refused"
"${DC[@]}" exec -T "$SVC" psql -X -U phoenix_bootstrap -d "$DB" -Atqc 'select 1' 2>&1 | tail -1
qb -c "SELECT 'hba '||type||' '||array_to_string(user_name,',')||' '||coalesce(address,'-')||' '||auth_method FROM pg_hba_file_rules WHERE type IS NOT NULL ORDER BY line_number;"

apply_one() {
  local f="$1" name digest ledger existing
  name="$(basename "$f")"; digest="$(sha256sum "$f" | awk '{print $1}')"
  ledger="$(qb -c "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;")"
  existing=""; [ "$ledger" = "t" ] && existing="$(qb -c "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name='$name';")"
  if [ -n "$existing" ]; then
    [ "$existing" = "$digest" ] && { echo "SKIP $name checksum verified"; return 0; }
    echo "REFUSED $name checksum changed"; return 3
  fi
  if sed '1{/^[[:space:]]*BEGIN;[[:space:]]*$/d;}; ${/^[[:space:]]*COMMIT;[[:space:]]*$/d;}' "$f" | grep -qE '^[[:space:]]*(BEGIN|COMMIT|ROLLBACK)[[:space:]]*;'; then echo "REFUSED nested transaction in $name"; return 4; fi
  { echo "BEGIN;"; echo "SELECT pg_advisory_xact_lock(2202,1);"
    [ "$ledger" = "t" ] && echo "DO \$g\$ BEGIN IF EXISTS (SELECT 1 FROM canonical_migrations.applied WHERE migration_name='$name') THEN RAISE EXCEPTION 'registered while waiting: $name'; END IF; END \$g\$;"
    sed '1{/^[[:space:]]*BEGIN;[[:space:]]*$/d;}; ${/^[[:space:]]*COMMIT;[[:space:]]*$/d;}' "$f"
    echo "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$digest');"
    echo "COMMIT;"; } | qb -f - >/dev/null || { echo "FAILED $name"; return 5; }
  echo "APPLIED $name sha256=$digest"
}
step "A3b migrations 0001-0009 (fresh)"
for f in "$ROOT"/migrations/canonical/*.sql; do apply_one "$f" || { echo "STOP migration"; exit 3; }; done
step "A3c migrations 0001-0009 (repeat must skip)"
for f in "$ROOT"/migrations/canonical/*.sql; do apply_one "$f" || { echo "STOP repeat"; exit 3; }; done

step "A3d provision local login roles (db.ps1 Provision-LocalRoles SQL; secrets substituted in-pipe)"
awk -F= 'NR==FNR { s[$1]=$2; next }
  { gsub(/__MIGRATOR__/, s["PHOENIX_LOCAL_MIGRATOR_PASSWORD"]); gsub(/__APP__/, s["PHOENIX_LOCAL_APP_PASSWORD"]);
    gsub(/__READER__/, s["PHOENIX_LOCAL_READER_PASSWORD"]); gsub(/__BINDER__/, s["PHOENIX_LOCAL_BINDER_PASSWORD"]);
    gsub(/__BACKUP__/, s["PHOENIX_LOCAL_BACKUP_PASSWORD"]); print }' "$ROOT/.local-roles.env" - <<'SQL' | qb -f - >/dev/null && echo "PASS roles provisioned"
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_migrator_local') THEN CREATE ROLE phoenix_canonical_migrator_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__MIGRATOR__'; ELSE ALTER ROLE phoenix_canonical_migrator_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__MIGRATOR__'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_app_local') THEN CREATE ROLE phoenix_canonical_app_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__APP__'; ELSE ALTER ROLE phoenix_canonical_app_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__APP__'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_reader_local') THEN CREATE ROLE phoenix_canonical_reader_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__READER__'; ELSE ALTER ROLE phoenix_canonical_reader_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__READER__'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_context_binder_local') THEN CREATE ROLE phoenix_canonical_context_binder_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__BINDER__'; ELSE ALTER ROLE phoenix_canonical_context_binder_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__BINDER__'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_backup_local') THEN CREATE ROLE phoenix_canonical_backup_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '__BACKUP__'; ELSE ALTER ROLE phoenix_canonical_backup_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '__BACKUP__'; END IF;
END
$roles$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_context_binder_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_backup_runtime TO phoenix_canonical_backup_local WITH INHERIT TRUE, SET FALSE;
SQL

step "A3e least-privilege login checks (each role over its own SCRAM login)"
chk() { local r; r="$(qu "$1" -c "$2" 2>&1 | tail -1)"; [ "$r" = "t" ] && echo "PASS $1" || echo "FAIL $1: $r"; }
chk phoenix_canonical_migrator_local "SELECT has_schema_privilege(current_user,'core','CREATE') AND has_schema_privilege(current_user,'education','CREATE') AND has_schema_privilege(current_user,'identity','CREATE') AND has_table_privilege(current_user,'canonical_migrations.applied','INSERT') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user);"
chk phoenix_canonical_app_local "SELECT has_schema_privilege(current_user,'education','USAGE') AND NOT has_schema_privilege(current_user,'education','CREATE') AND NOT has_schema_privilege(current_user,'canonical_migrations','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND (SELECT count(*)=0 FROM information_schema.role_table_grants WHERE grantee='phoenix_canonical_app' AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE'));"
chk phoenix_canonical_reader_local "SELECT has_schema_privilege(current_user,'identity','USAGE') AND NOT has_schema_privilege(current_user,'identity','CREATE') AND has_table_privilege(current_user,'canonical_migrations.applied','SELECT') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user);"
chk phoenix_canonical_context_binder_local "SELECT has_function_privilege(current_user,'auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid)','EXECUTE') AND NOT has_table_privilege(current_user,'auth.session_contexts','SELECT') AND NOT has_schema_privilege(current_user,'core','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user);"
chk phoenix_canonical_backup_local "SELECT (SELECT rolbypassrls FROM pg_roles WHERE rolname='phoenix_canonical_backup_local') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AND has_table_privilege(current_user,'core.people','SELECT') AND NOT has_table_privilege(current_user,'core.people','INSERT');"

step "A3f six original acceptance suites on the dev database (each rolls back)"
for t in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql; do
  if qb -f - < "$ROOT/tests/$t" >/dev/null 2>/tmp/claude_a_err_$V.txt; then echo "PASS $t"; else echo "FAIL $t: $(grep -m1 -o 'ERROR:.*' /tmp/claude_a_err_$V.txt)"; fi
done

step "A3g final catalog read-back"
qb -c "SELECT 'ledger '||migration_name||' '||sha256 FROM canonical_migrations.applied ORDER BY 1;
SELECT 'ledger_count='||count(*) FROM canonical_migrations.applied;
SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity');
SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity');
SELECT 'app_write_grants='||count(*) FROM information_schema.role_table_grants WHERE grantee='phoenix_canonical_app' AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');
SELECT 'public_execute_functions='||count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity') AND has_function_privilege('public',p.oid,'EXECUTE');
SELECT 'probe_schema_absent='||(to_regnamespace('acceptance_probe') IS NULL);"
echo "domain_rows=$(qb -c "SELECT coalesce(sum((xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', schemaname, tablename), false, true, '')))[1]::text::bigint),0) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity');")"
echo; echo "END TASK A PostgreSQL $V $(date '+%F %T %z')"
