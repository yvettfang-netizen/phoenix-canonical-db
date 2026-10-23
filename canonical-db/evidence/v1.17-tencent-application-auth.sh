#!/usr/bin/env bash
set -euo pipefail
umask 077

root=/home/ubuntu/phoenix-canonical-db-deploy
deploy="$root/deploy/tencent"
service_id=018f0000-0000-7000-8000-00000000a001
service_label=phoenix-nonprod-management-service
cd "$deploy"

echo '=== V1.17 isolated application authorization ==='
echo "HOST=$(hostname)"
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "DEPLOY_PATH=$root"
echo "SERVICE_PRINCIPAL_CLASS=SYNTHETIC_NONPRODUCTION"
echo "SERVICE_PRINCIPAL_ID=$service_id"

[ "$(stat -c %a .env)" = 600 ] || { echo 'FAIL .env mode is not 600' >&2; exit 1; }
echo 'ENV_MODE=600'
if grep -q '^PHOENIX_DB_SERVICE_PRINCIPAL_ID=.' .env; then echo 'SERVICE_ID_CONFIGURED_BEFORE=yes'; else echo 'SERVICE_ID_CONFIGURED_BEFORE=no'; fi
if grep -q '^PHOENIX_DB_SERVICE_PRINCIPAL_LABEL=.' .env; then echo 'SERVICE_LABEL_CONFIGURED_BEFORE=yes'; else echo 'SERVICE_LABEL_CONFIGURED_BEFORE=no'; fi
docker inspect -f 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} PORTS={{json .HostConfig.PortBindings}}' tencent-postgres-1

if grep -q "^PHOENIX_DB_SERVICE_PRINCIPAL_ID=$service_id$" .env &&
   grep -q "^PHOENIX_DB_SERVICE_PRINCIPAL_LABEL=$service_label$" .env; then
  echo 'ENV_CONFIG_ACTION=preserved_existing_exact_values'
else
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  env_backup="$deploy/.env.bak-v117-$stamp"
  cp -p .env "$env_backup"
  chmod 600 "$env_backup"
  echo "ENV_BACKUP=$env_backup"
  echo "ENV_BACKUP_MODE=$(stat -c %a "$env_backup")"

  tmp_env="$(mktemp "$deploy/.env.v117.XXXXXX")"
  awk '!/^PHOENIX_DB_SERVICE_PRINCIPAL_ID=/ && !/^PHOENIX_DB_SERVICE_PRINCIPAL_LABEL=/' .env > "$tmp_env"
  printf 'PHOENIX_DB_SERVICE_PRINCIPAL_ID=%s\nPHOENIX_DB_SERVICE_PRINCIPAL_LABEL=%s\n' "$service_id" "$service_label" >> "$tmp_env"
  chmod 600 "$tmp_env"
  mv -f "$tmp_env" .env
  echo 'ENV_CONFIG_ACTION=backed_up_and_updated'
fi
echo "ENV_MODE_AFTER=$(stat -c %a .env)"
grep -q "^PHOENIX_DB_SERVICE_PRINCIPAL_ID=$service_id$" .env
grep -q "^PHOENIX_DB_SERVICE_PRINCIPAL_LABEL=$service_label$" .env
echo 'SERVICE_CONFIG_VALIDATED=yes'

echo '=== repeat-safe installer and service principal registration ==='
timeout --signal=TERM --kill-after=5s 300s ./install.sh

set -a
. ./.env
set +a
binder_pgpass=/tmp/phoenix-v117-binder.pgpass
app_pgpass=/tmp/phoenix-v117-app.pgpass
bootstrap_pgpass=/tmp/phoenix-v117-bootstrap.pgpass
cleanup() {
  docker compose --env-file .env exec -T postgres sh -c "rm -f '$binder_pgpass' '$app_pgpass' '$bootstrap_pgpass'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '%s\n' "*:*:*:phoenix_canonical_binder_runtime:$PHOENIX_DB_BINDER_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$binder_pgpass'; chmod 600 '$binder_pgpass'"
printf '%s\n' "*:*:*:phoenix_canonical_app_runtime:$PHOENIX_DB_APP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$app_pgpass'; chmod 600 '$app_pgpass'"
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"

dc() { docker compose --env-file .env "$@"; }
binder_psql() {
  dc exec -T -e "PGPASSFILE=$binder_pgpass" postgres psql -X -h 127.0.0.1 \
    -U phoenix_canonical_binder_runtime -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}
app_psql() {
  dc exec -T -e "PGPASSFILE=$app_pgpass" postgres psql -X -h 127.0.0.1 \
    -U phoenix_canonical_app_runtime -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}
bootstrap_psql() {
  dc exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres psql -X -h 127.0.0.1 \
    -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}

echo '=== separate LOGIN proof and one-use ticket flow ==='
binder_psql -Atqc "SELECT 'BINDER_LOGIN='||session_user||'/'||current_user;"
app_psql -Atqc "SELECT 'APP_LOGIN='||session_user||'/'||current_user;"
ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$service_id',NULL,NULL,'INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$service_id');")"
[ -n "$ticket" ] || { echo 'FAIL ticket not issued' >&2; exit 1; }
echo 'TICKET_ISSUED=yes ttl_seconds=45'

printf "SELECT auth.redeem_context_ticket('%s','%s');\nSELECT 'PRINCIPAL_MATCH='||(auth.current_principal_id()='%s');\nSELECT 'CHANNEL='||auth.current_channel();\nSELECT 'ACTOR_IS_NULL='||(auth.current_actor_person_id() IS NULL);\nSELECT 'FAMILY_IS_NULL='||(auth.current_family_id() IS NULL);\nSELECT auth.clear_context();\nSELECT 'CLEARED='||(auth.current_principal_id() IS NULL);\n" \
  "$ticket" "$service_id" "$service_id" |
  app_psql -At -f -

set +e
reuse_out="$(app_psql -Atqc "SELECT auth.redeem_context_ticket('$ticket','$service_id');" 2>&1)"
reuse_rc=$?
set -e
printf '%s\n' "$reuse_out" | grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED'
[ "$reuse_rc" -ne 0 ]
echo 'PASS ticket reuse rejected'

other_ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$service_id',NULL,NULL,'INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$service_id');")"
set +e
wrong_target_out="$(app_psql -Atqc "SELECT auth.redeem_context_ticket('$other_ticket','018f0000-0000-7000-8000-00000000a099');" 2>&1)"
wrong_target_rc=$?
set -e
printf '%s\n' "$wrong_target_out" | grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED'
[ "$wrong_target_rc" -ne 0 ]
echo 'PASS wrong-principal redemption rejected'
printf "SELECT auth.redeem_context_ticket('%s','%s');\nSELECT 'CORRECT_TARGET_AFTER_REJECTION='||(auth.current_principal_id()='%s');\nSELECT auth.clear_context();\n" \
  "$other_ticket" "$service_id" "$service_id" |
  app_psql -At -f -

set +e
wrong_channel_out="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$service_id',NULL,NULL,'FAMILY',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$service_id');" 2>&1)"
wrong_channel_rc=$?
set -e
printf '%s\n' "$wrong_channel_out" | grep -q 'CONTEXT_PRINCIPAL_CHANNEL_MISMATCH'
[ "$wrong_channel_rc" -ne 0 ]
echo 'PASS SERVICE/FAMILY channel mismatch rejected'

set +e
direct_out="$(app_psql -Atqc "INSERT INTO core.families(family_id,display_name) VALUES ('018f0000-0000-7000-8000-00000000a011','Forbidden Direct Write');" 2>&1)"
direct_rc=$?
set -e
printf '%s\n' "$direct_out" | grep -qi 'permission denied'
[ "$direct_rc" -ne 0 ]
echo 'PASS app direct table write rejected'

app_psql -Atqc "SELECT 'APP_DIRECT_DML_TABLES='||count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND c.relkind IN ('r','p') AND (has_table_privilege(current_user,c.oid,'INSERT') OR has_table_privilege(current_user,c.oid,'UPDATE') OR has_table_privilege(current_user,c.oid,'DELETE'));"
bootstrap_psql -Atqc "SELECT 'PUBLIC_CONTROLLED_FUNCTIONS='||count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE n.nspname='auth' AND p.proname IN ('issue_context_ticket','redeem_context_ticket','install_service_principal','bind_context') AND a.grantee=0 AND a.privilege_type='EXECUTE';"

echo '=== installed-state and zero-business-data proof ==='
bootstrap_psql -Atqc "BEGIN READ ONLY; SELECT 'SERVICE_ROWS='||count(*) FROM auth.principals WHERE principal_id='$service_id' AND principal_kind='SERVICE' AND person_id IS NULL AND status='ACTIVE'; SELECT 'OTHER_PRINCIPALS='||count(*) FROM auth.principals WHERE principal_id<>'$service_id'; SELECT 'PEOPLE='||count(*) FROM core.people; SELECT 'FAMILIES='||count(*) FROM core.families; SELECT 'MEMBERSHIPS='||count(*) FROM core.family_memberships; SELECT 'STUDENTS='||count(*) FROM core.student_profiles; SELECT 'CONSENTS='||count(*) FROM consent.grants; SELECT 'CASES='||count(*) FROM casework.cases; SELECT 'DOCUMENTS='||count(*) FROM docs.documents; SELECT 'EDUCATION_APPLICATIONS='||count(*) FROM education.applications; SELECT 'IDENTITY_CASES='||count(*) FROM identity.cases; SELECT 'LEARNING_ENROLLMENTS='||count(*) FROM learning.enrollment; COMMIT;"

echo '=== health, backup, fresh restore, and isolation ==='
./health.sh
backup_out="$(./backup.sh)"
printf '%s\n' "$backup_out"
backup_path="$(printf '%s\n' "$backup_out" | sed -n 's/^BACKUP //p')"
[ -n "$backup_path" ]
timeout --signal=TERM --kill-after=5s 300s ./restore_drill.sh "$backup_path"
./alert_check.sh
docker inspect -f 'FINAL_CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} PORTS={{json .HostConfig.PortBindings}}' tencent-postgres-1
echo "ENV_FINAL_MODE=$(stat -c %a .env)"
echo 'RESULT=PASS_SYNTHETIC_APPLICATION_AUTHORIZATION'
