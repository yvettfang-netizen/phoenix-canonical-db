#!/usr/bin/env bash
# Enterprise Database V2.0 P2 permanent regression. Synthetic data and split
# LOGIN accounts only; every service context uses a one-use binder ticket.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
SERVICE=018f0000-0000-7000-8000-000000028001
WRONG_SERVICE=018f0000-0000-7000-8000-000000002001
ADVISOR=018f0000-0000-7000-8000-000000002004
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
SUBJECT_A1=018f0000-0000-7000-8000-000000001003
SUBJECT_A2=018f0000-0000-7000-8000-000000026101
SUBJECT_B=018f0000-0000-7000-8000-000000001006
CLIENT=018f0000-0000-7000-8000-000000026302
DEAL=018f0000-0000-7000-8000-000000027401
PROJECT1=018f0000-0000-7000-8000-000000028101
PROJECT2=018f0000-0000-7000-8000-000000028102
PROJECT_BAD=018f0000-0000-7000-8000-000000028103
PSUB1=018f0000-0000-7000-8000-000000028201
PSUB2=018f0000-0000-7000-8000-000000028202
PSUB_BAD=018f0000-0000-7000-8000-000000028203
DOMAIN1=018f0000-0000-7000-8000-000000028301
DOMAIN2=018f0000-0000-7000-8000-000000028302
ASSIGNMENT=018f0000-0000-7000-8000-000000028401
PARTY=018f0000-0000-7000-8000-000000028411
MILESTONE=018f0000-0000-7000-8000-000000028421
DELIVERABLE=018f0000-0000-7000-8000-000000028431
TASK=018f0000-0000-7000-8000-000000028501
TASK_LATE=018f0000-0000-7000-8000-000000028502

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U "$APP"    -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local principal="$1" family="$2" nonce="$3" file="$4" ticket family_sql
  family_sql=NULL; [ "$family" = NULL ] || family_sql="'$family'::uuid"
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',NULL,$family_sql,'INTERNAL',clock_timestamp()+interval '45 seconds','$nonce','$principal')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"; cat "$file"; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

before="$(bootstrap_psql -Atqc "SELECT (SELECT count(*) FROM casework.cases)||'|'||(SELECT count(*) FROM learning.enrollment)||'|'||(SELECT count(*) FROM consent.grants)")"
test "$(bootstrap_psql -Atqc "SELECT auth.install_service_principal('$SERVICE','canonical_service_v2')")" = t

cat >/tmp/f10-0028-create.sql <<SQL
SELECT 'PROJECT1='||service.create_project('$PROJECT1','$CLIENT','$FAMILY_A','$DEAL','SVC_028_A','Synthetic Multi-domain Service Project','MULTI_DOMAIN',clock_timestamp(),clock_timestamp()+interval '90 days','018f0000-0000-7000-8000-000000028601');
SELECT 'PROJECT2='||service.create_project('$PROJECT2','$CLIENT','$FAMILY_A',NULL,'SVC_028_B','Synthetic Second Service Project','EDUCATION',NULL,NULL,'018f0000-0000-7000-8000-000000028602');
SELECT 'PLAN='||service.transition_project('$PROJECT1','PLANNED','018f0000-0000-7000-8000-000000028603');
SELECT 'ACTIVATE='||service.transition_project('$PROJECT1','ACTIVE','018f0000-0000-7000-8000-000000028604');
SELECT 'SUBJECT1='||service.add_project_subject('$PSUB1','$PROJECT1','$SUBJECT_A1','EDUCATION','018f0000-0000-7000-8000-000000028605');
SELECT 'SUBJECT2='||service.add_project_subject('$PSUB2','$PROJECT1','$SUBJECT_A2','WEALTH','018f0000-0000-7000-8000-000000028606');
SELECT 'DOMAIN1='||service.add_project_domain('$DOMAIN1','$PROJECT1','EDUCATION','018f0000-0000-7000-8000-000000028607');
SELECT 'DOMAIN2='||service.add_project_domain('$DOMAIN2','$PROJECT1','WEALTH','018f0000-0000-7000-8000-000000028608');
SELECT 'ASSIGN='||service.assign_project('$ASSIGNMENT','$PROJECT1','$ADVISOR','PROJECT_MANAGER','018f0000-0000-7000-8000-000000028609');
SELECT 'PARTY='||service.add_project_party('$PARTY','$PROJECT1','FAMILY_ADMIN','$SUBJECT_A1',NULL::uuid,clock_timestamp()+interval '90 days','018f0000-0000-7000-8000-000000028620');
SELECT 'MILESTONE='||service.create_milestone('$MILESTONE','$PROJECT1','MS_028_READY','Synthetic readiness milestone',clock_timestamp()+interval '10 days','018f0000-0000-7000-8000-000000028621');
SELECT 'MILESTONE_ACHIEVED='||service.transition_milestone('$MILESTONE','ACHIEVED','018f0000-0000-7000-8000-000000028622');
SELECT 'DELIVERABLE='||service.create_deliverable('$DELIVERABLE','$PROJECT1','$PSUB1',NULL::uuid,'SYNTHETIC_BLUEPRINT',clock_timestamp()+interval '7 days','018f0000-0000-7000-8000-000000028623');
SELECT 'DELIVERABLE_READY='||service.transition_deliverable('$DELIVERABLE','READY','018f0000-0000-7000-8000-000000028624');
SELECT 'DELIVERABLE_DELIVERED='||service.transition_deliverable('$DELIVERABLE','DELIVERED','018f0000-0000-7000-8000-000000028625');
SELECT 'DELIVERABLE_ACCEPTED='||service.transition_deliverable('$DELIVERABLE','ACCEPTED','018f0000-0000-7000-8000-000000028626');
SELECT 'TASK='||service.create_task('$TASK','$PROJECT1','EDUCATION_APPLICATION_PREP','Synthetic application preparation','HIGH','$ADVISOR',clock_timestamp()+interval '14 days','018f0000-0000-7000-8000-000000028610');
SELECT 'TASK_START='||service.transition_task('$TASK','IN_PROGRESS','WORK_STARTED','018f0000-0000-7000-8000-000000028611');
SELECT 'TASK_BLOCK='||service.transition_task('$TASK','BLOCKED','AWAITING_SYNTHETIC_INPUT','018f0000-0000-7000-8000-000000028612');
SELECT 'TASK_RESUME='||service.transition_task('$TASK','IN_PROGRESS','SYNTHETIC_INPUT_RECEIVED','018f0000-0000-7000-8000-000000028613');
SELECT 'TASK_COMPLETE='||service.transition_task('$TASK','COMPLETED','WORK_COMPLETED','018f0000-0000-7000-8000-000000028614');
SELECT 'PROJECT_COMPLETE='||service.transition_project('$PROJECT1','COMPLETED','018f0000-0000-7000-8000-000000028615');
SELECT 'LATE_TASK='||service.create_task('$TASK_LATE','$PROJECT1','LATE_WORK','Late work must fail','LOW',NULL,NULL,'018f0000-0000-7000-8000-000000028616');
SQL
out="$(run_session "$SERVICE" "$FAMILY_A" 018f0000-0000-7000-8000-000000028701 /tmp/f10-0028-create.sql)"
for expected in PROJECT1=true PROJECT2=true PLAN=true ACTIVATE=true SUBJECT1=true SUBJECT2=true DOMAIN1=true DOMAIN2=true ASSIGN=true PARTY=true MILESTONE=true MILESTONE_ACHIEVED=true DELIVERABLE=true DELIVERABLE_READY=true DELIVERABLE_DELIVERED=true DELIVERABLE_ACCEPTED=true TASK=true TASK_START=true TASK_BLOCK=true TASK_RESUME=true TASK_COMPLETE=true PROJECT_COMPLETE=true LATE_TASK=false; do expect_line "$expected" "$out"; done

shape="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(*) FROM service.projects WHERE family_id='$FAMILY_A')||'|'||
  (SELECT count(*) FROM service.project_subjects WHERE service_project_id='$PROJECT1')||'|'||
  (SELECT count(*) FROM service.project_domains WHERE service_project_id='$PROJECT1')||'|'||
  (SELECT count(*) FROM service.project_assignments WHERE service_project_id='$PROJECT1' AND status='ACTIVE')||'|'||
  (SELECT count(*) FROM service.project_parties WHERE service_project_id='$PROJECT1')||'|'||
  (SELECT status FROM service.project_milestones WHERE project_milestone_id='$MILESTONE')||'|'||
  (SELECT status FROM service.deliverables WHERE deliverable_id='$DELIVERABLE')||'|'||
  (SELECT task_status FROM service.tasks WHERE task_id='$TASK')||'|'||
  (SELECT access_status FROM service.project_subjects WHERE project_subject_id='$PSUB1')")"
test "$shape" = '2|2|2|1|1|ACHIEVED|ACCEPTED|COMPLETED|REFERENCE_ONLY' || { echo "FAIL service shape=$shape" >&2; exit 1; }
echo 'PASS one Family has multiple Service Projects; Project Parties, Subjects, Domains, Milestones, Deliverables and Tasks use controlled lifecycles'

cat >/tmp/f10-0028-cross.sql <<SQL
SELECT 'CROSS_PROJECT='||service.create_project('$PROJECT_BAD','$CLIENT','$FAMILY_A',NULL,'SVC_028_X','Forbidden Cross Family','EDUCATION',NULL,NULL,'018f0000-0000-7000-8000-000000028617');
SELECT 'CROSS_SUBJECT='||service.add_project_subject('$PSUB_BAD','$PROJECT1','$SUBJECT_B','GENERAL','018f0000-0000-7000-8000-000000028618');
SQL
out="$(run_session "$SERVICE" "$FAMILY_B" 018f0000-0000-7000-8000-000000028702 /tmp/f10-0028-cross.sql)"
expect_line 'CROSS_PROJECT=false' "$out"; expect_line 'CROSS_SUBJECT=false' "$out"

cat >/tmp/f10-0028-wrong-service.sql <<SQL
SELECT 'WRONG_SERVICE='||service.create_project('$PROJECT_BAD','$CLIENT','$FAMILY_A',NULL,'SVC_028_W','Wrong Service','EDUCATION',NULL,NULL,'018f0000-0000-7000-8000-000000028619');
SQL
out="$(run_session "$WRONG_SERVICE" "$FAMILY_A" 018f0000-0000-7000-8000-000000028703 /tmp/f10-0028-wrong-service.sql)"
expect_line 'WRONG_SERVICE=false' "$out"

if app_psql -Atqc "INSERT INTO service.tasks(task_id,service_project_id,task_type,task_title,task_status,priority,created_by_principal_id,updated_by_principal_id) VALUES('$TASK_LATE','$PROJECT2','FORGED_TASK','Forbidden','PENDING','LOW','$SERVICE','$SERVICE')" >/tmp/f10-0028-acl.out 2>&1; then
  echo 'FAIL app direct Service Task INSERT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0028-acl.out

event_update="$(bootstrap_psql -Atqc "UPDATE service.task_events SET reason_code='FORGED' WHERE task_id='$TASK'" 2>&1 || true)"
grep -q 'SERVICE_EVENT_IMMUTABLE' <<<"$event_update" || { echo "FAIL event immutability=$event_update" >&2; exit 1; }

cross_deliverable="$(bootstrap_psql -Atqc "INSERT INTO service.deliverables(deliverable_id,service_project_id,project_subject_id,deliverable_kind,status,created_by_principal_id,updated_by_principal_id) VALUES('018f0000-0000-7000-8000-000000028901','$PROJECT2','$PSUB1','SYNTHETIC_DELIVERABLE','DRAFT','$SERVICE','$SERVICE')" 2>&1 || true)"
grep -qi 'foreign key constraint' <<<"$cross_deliverable" || { echo "FAIL cross-project deliverable target=$cross_deliverable" >&2; exit 1; }

after="$(bootstrap_psql -Atqc "SELECT (SELECT count(*) FROM casework.cases)||'|'||(SELECT count(*) FROM learning.enrollment)||'|'||(SELECT count(*) FROM consent.grants)")"
test "$after" = "$before" || { echo "FAIL P2 mutated casework/learning/consent before=$before after=$after" >&2; exit 1; }

authority="$(bootstrap_psql -Atqc "SELECT
  (NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='service' AND table_name='projects' AND column_name='contract_id'))::text||'|'||
  (NOT EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid=c.conrelid JOIN pg_namespace n ON n.oid=r.relnamespace JOIN pg_class f ON f.oid=c.confrelid JOIN pg_namespace fn ON fn.oid=f.relnamespace WHERE n.nspname='service' AND fn.nspname IN ('casework','learning')))::text")"
test "$authority" = 'true|true' || { echo "FAIL P2 authority boundary=$authority" >&2; exit 1; }

acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','service.projects','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','service.tasks','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_function_privilege('public','service.create_project(uuid,uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.create_project(uuid,uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,uuid)','EXECUTE')::text")"
test "$acl" = 'false|false|false|true' || { echo "FAIL P2 ACL=$acl" >&2; exit 1; }

audit="$(bootstrap_psql -Atqc "SELECT count(*) FILTER (WHERE decision='ALLOW')||'|'||count(*) FILTER (WHERE decision='DENY') FROM audit.access_events WHERE resource_kind LIKE 'SERVICE_%'")"
IFS='|' read -r allow_count deny_count <<<"$audit"; test "$allow_count" -gt 0 && test "$deny_count" -gt 0
echo 'PASS 0028 tenant isolation, exact service authority, immutable events, no implicit sensitive access, exact ACL and allow/deny audit regression'

