#!/usr/bin/env bash
# M4 permanent regression. Synthetic rows and split LOGIN accounts only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
SERVICE=018f0000-0000-7000-8000-000000028001
FAMILY_A=018f0000-0000-7000-8000-000000000001
SUBJECT=018f0000-0000-7000-8000-000000001003
ADVISOR=018f0000-0000-7000-8000-000000002004
ORG=018f0000-0000-7000-8000-000000030201
PROJECT=018f0000-0000-7000-8000-000000028102
AUTH1=018f0000-0000-7000-8000-000000034101
AUTH2=018f0000-0000-7000-8000-000000034102
PSUB1=018f0000-0000-7000-8000-000000034201
PSUB2=018f0000-0000-7000-8000-000000034202
PARTY1=018f0000-0000-7000-8000-000000034301
PARTY2=018f0000-0000-7000-8000-000000034302
ASSIGN1=018f0000-0000-7000-8000-000000034401
ASSIGN2=018f0000-0000-7000-8000-000000034402
DIGEST=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U "$APP"    -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local nonce="$1" file="$2" ticket
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$SERVICE',NULL,'$FAMILY_A'::uuid,'INTERNAL',clock_timestamp()+interval '45 seconds','$nonce','$SERVICE')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$SERVICE"; cat "$file"; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

cat >/tmp/f10-0034-open.sql <<SQL
SELECT 'PLAN='||service.transition_project('$PROJECT','PLANNED','018f0000-0000-7000-8000-000000034501');
SELECT 'ACTIVE='||service.transition_project('$PROJECT','ACTIVE','018f0000-0000-7000-8000-000000034502');
SELECT 'HEALTH_NO_AUTH='||service.add_project_subject_authorized('$PSUB1','$PROJECT','$SUBJECT','HEALTH',NULL,'018f0000-0000-7000-8000-000000034503');
SELECT 'AUTHORIZE1='||service.register_project_subject_authorization('$AUTH1','$PROJECT','$SUBJECT','PATIENT_SELF','$SUBJECT','$DIGEST',clock_timestamp()+interval '30 days','018f0000-0000-7000-8000-000000034504');
SELECT 'HEALTH1='||service.add_project_subject_authorized('$PSUB1','$PROJECT','$SUBJECT','HEALTH','$AUTH1','018f0000-0000-7000-8000-000000034505');
SELECT 'PARTY1='||service.add_project_party('$PARTY1','$PROJECT','SERVICE_PROVIDER',NULL::uuid,'$ORG',NULL,'018f0000-0000-7000-8000-000000034506');
SELECT 'ASSIGN1='||service.assign_project('$ASSIGN1','$PROJECT','$ADVISOR','SPECIALIST','018f0000-0000-7000-8000-000000034507');
SELECT 'REVOKE_AUTH='||service.revoke_project_subject_authorization('$AUTH1','018f0000-0000-7000-8000-000000034508');
SELECT 'REUSE_REVOKED='||service.add_project_subject_authorized('$PSUB2','$PROJECT','$SUBJECT','HEALTH','$AUTH1','018f0000-0000-7000-8000-000000034509');
SQL
out="$(run_session 018f0000-0000-7000-8000-000000034601 /tmp/f10-0034-open.sql)"
for expected in PLAN=true ACTIVE=true HEALTH_NO_AUTH=false AUTHORIZE1=true HEALTH1=true PARTY1=true ASSIGN1=true REVOKE_AUTH=true REUSE_REVOKED=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0034-regrant.sql <<SQL
SELECT 'AUTHORIZE2='||service.register_project_subject_authorization('$AUTH2','$PROJECT','$SUBJECT','PATIENT_SELF','$SUBJECT','$DIGEST',clock_timestamp()+interval '30 days','018f0000-0000-7000-8000-000000034511');
SELECT 'HEALTH2='||service.add_project_subject_authorized('$PSUB2','$PROJECT','$SUBJECT','HEALTH','$AUTH2','018f0000-0000-7000-8000-000000034512');
SELECT 'END_PARTY='||service.end_project_party('$PARTY1','018f0000-0000-7000-8000-000000034513');
SELECT 'PARTY2='||service.add_project_party('$PARTY2','$PROJECT','REFERRING_PARTNER',NULL::uuid,'$ORG',NULL,'018f0000-0000-7000-8000-000000034514');
SELECT 'END_ASSIGN='||service.end_project_assignment('$ASSIGN1','018f0000-0000-7000-8000-000000034515');
SELECT 'ASSIGN2='||service.assign_project('$ASSIGN2','$PROJECT','$ADVISOR','SPECIALIST','018f0000-0000-7000-8000-000000034516');
SELECT 'COMPLETE='||service.transition_project('$PROJECT','COMPLETED','018f0000-0000-7000-8000-000000034517');
SELECT 'CLOSED_SUBJECT='||service.add_project_subject_authorized('018f0000-0000-7000-8000-000000034203','$PROJECT','$SUBJECT','GENERAL',NULL,'018f0000-0000-7000-8000-000000034518');
SELECT 'CLOSED_ASSIGN='||service.assign_project('018f0000-0000-7000-8000-000000034403','$PROJECT','$ADVISOR','OBSERVER','018f0000-0000-7000-8000-000000034519');
SQL
out="$(run_session 018f0000-0000-7000-8000-000000034602 /tmp/f10-0034-regrant.sql)"
for expected in AUTHORIZE2=true HEALTH2=true END_PARTY=true PARTY2=true END_ASSIGN=true ASSIGN2=true COMPLETE=true CLOSED_SUBJECT=false CLOSED_ASSIGN=false; do expect_line "$expected" "$out"; done

state="$(bootstrap_psql -Atqc "SELECT
  (SELECT project_status FROM service.projects WHERE service_project_id='$PROJECT')||'|'||
  (SELECT string_agg(status,',' ORDER BY project_subject_id) FROM service.project_subjects WHERE service_project_id='$PROJECT' AND data_scope='HEALTH')||'|'||
  (SELECT string_agg(status,',' ORDER BY project_party_id) FROM service.project_parties WHERE service_project_id='$PROJECT')||'|'||
  (SELECT string_agg(status,',' ORDER BY project_assignment_id) FROM service.project_assignments WHERE service_project_id='$PROJECT')||'|'||
  (SELECT string_agg(status,',' ORDER BY project_subject_authorization_id) FROM service.project_subject_authorizations WHERE service_project_id='$PROJECT')")"
test "$state" = 'COMPLETED|ENDED,ENDED|ENDED,ENDED|ENDED,ENDED|REVOKED,REVOKED' || { echo "FAIL M4 state=$state" >&2; exit 1; }

mutation="$(bootstrap_psql -Atqc "UPDATE service.project_subject_authorizations SET status='ACTIVE',revoked_at=NULL,revoked_by_principal_id=NULL WHERE project_subject_authorization_id='$AUTH1'" 2>&1 || true)"
grep -q 'SERVICE_PROJECT_AUTHORIZATION_TERMINAL' <<<"$mutation" || { echo "FAIL authorization reactivation=$mutation" >&2; exit 1; }
delete_history="$(bootstrap_psql -Atqc "DELETE FROM service.project_subjects WHERE project_subject_id='$PSUB1'" 2>&1 || true)"
grep -q 'SERVICE_PROJECT_HISTORY_TERMINAL' <<<"$delete_history" || { echo "FAIL subject history delete=$delete_history" >&2; exit 1; }
if app_psql -Atqc "SELECT count(*) FROM service.project_subject_authorizations" >/tmp/f10-0034-acl.out 2>&1; then
  echo 'FAIL app direct authorization SELECT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0034-acl.out
acl="$(bootstrap_psql -Atqc "SELECT
  has_function_privilege('public','service.add_project_subject_authorized(uuid,uuid,uuid,text,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.add_project_subject(uuid,uuid,uuid,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.add_project_subject_authorized(uuid,uuid,uuid,text,uuid,uuid)','EXECUTE')::text||'|'||
  (NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='service' AND table_name='projects' AND column_name='contract_id'))::text")"
test "$acl" = 'false|false|true|true' || { echo "FAIL M4 ACL/authority=$acl" >&2; exit 1; }
echo 'PASS M4 project party/subject/domain/assignment governance, patient authorization, terminal history, closed-project denial and no Finance FK'
