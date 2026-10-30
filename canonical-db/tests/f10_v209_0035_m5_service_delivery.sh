#!/usr/bin/env bash
# V2.0 M5 permanent regression: split LOGIN accounts, one-use tickets and
# synthetic Service delivery metadata only. No document body is stored here.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
SERVICE=018f0000-0000-7000-8000-000000028001
REVIEWER=018f0000-0000-7000-8000-000000028002
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
SUBJECT=018f0000-0000-7000-8000-000000026101
CLIENT=018f0000-0000-7000-8000-000000026302
PROJECT=018f0000-0000-7000-8000-000000035101
PSUB=018f0000-0000-7000-8000-000000035201
DOMAIN=018f0000-0000-7000-8000-000000035301
ASSIGN_SERVICE=018f0000-0000-7000-8000-000000035401
ASSIGN_REVIEWER=018f0000-0000-7000-8000-000000035402
TEMPLATE=018f0000-0000-7000-8000-000000035420
MILESTONE=018f0000-0000-7000-8000-000000035421
TASK=018f0000-0000-7000-8000-000000035501
DOCUMENT=018f0000-0000-7000-8000-000000035431
VERSION=018f0000-0000-7000-8000-000000035432
DELIVERABLE=018f0000-0000-7000-8000-000000035433
WITHDRAWN_DELIVERABLE=018f0000-0000-7000-8000-000000035434
OLD_DOCUMENT=018f0000-0000-7000-8000-000000028432
OLD_VERSION=018f0000-0000-7000-8000-000000028433

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

cat >/tmp/f10-0035-create.sql <<SQL
SELECT 'PROJECT='||service.create_project('$PROJECT','$CLIENT','$FAMILY_A',NULL,'SVC_035_DELIVERY','Synthetic governed delivery project','EDUCATION',clock_timestamp(),clock_timestamp()+interval '60 days','018f0000-0000-7000-8000-000000035601');
SELECT 'PLAN='||service.transition_project('$PROJECT','PLANNED','018f0000-0000-7000-8000-000000035602');
SELECT 'ACTIVE='||service.transition_project('$PROJECT','ACTIVE','018f0000-0000-7000-8000-000000035603');
SELECT 'SUBJECT='||service.add_project_subject_authorized('$PSUB','$PROJECT','$SUBJECT','EDUCATION',NULL,'018f0000-0000-7000-8000-000000035604');
SELECT 'DOMAIN='||service.add_project_domain('$DOMAIN','$PROJECT','EDUCATION','018f0000-0000-7000-8000-000000035605');
SELECT 'ASSIGN_SERVICE='||service.assign_project('$ASSIGN_SERVICE','$PROJECT','$SERVICE','PROJECT_MANAGER','018f0000-0000-7000-8000-000000035606');
SELECT 'ASSIGN_REVIEWER='||service.assign_project('$ASSIGN_REVIEWER','$PROJECT','$REVIEWER','SPECIALIST','018f0000-0000-7000-8000-000000035607');
SELECT 'TEMPLATE='||service.register_milestone_template('$TEMPLATE','M5_DELIVERY_REVIEW',1,'EDUCATION','Synthetic governed delivery review');
SELECT 'MILESTONE='||service.create_milestone_from_template('$MILESTONE','$PROJECT','$TEMPLATE','M5_REVIEW_READY',clock_timestamp()+interval '14 days','018f0000-0000-7000-8000-000000035608');
SELECT 'TASK='||service.create_task('$TASK','$PROJECT','DELIVERY_PREPARATION','Prepare synthetic governed deliverable','HIGH','$SERVICE',clock_timestamp()+interval '7 days','018f0000-0000-7000-8000-000000035609');
SELECT 'TRANSFER='||service.transfer_task('$TASK','$REVIEWER','SPECIALIST_HANDOFF','018f0000-0000-7000-8000-000000035610');
SELECT 'TRANSFER_UNASSIGNED='||service.transfer_task('$TASK','018f0000-0000-7000-8000-000000002004','UNASSIGNED_HANDOFF','018f0000-0000-7000-8000-000000035611');
SELECT 'MILESTONE_ACHIEVED='||service.transition_milestone('$MILESTONE','ACHIEVED','018f0000-0000-7000-8000-000000035612');
SELECT 'DOCUMENT='||docs.create_document('$DOCUMENT','$FAMILY_A','$SUBJECT','EDUCATION','SYNTHETIC_SERVICE_DELIVERY',clock_timestamp()+interval '365 days');
SELECT 'VERSION='||docs.append_document_version('$VERSION','$DOCUMENT',1,'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','mock/service/v2/m5/delivery-v1',256);
SELECT 'DELIVERABLE='||service.create_versioned_deliverable('$DELIVERABLE','$PROJECT','$PSUB','$DOCUMENT','$VERSION','GROWTH_BLUEPRINT',clock_timestamp()+interval '10 days','018f0000-0000-7000-8000-000000035613');
SELECT 'SUBMIT='||service.submit_deliverable('$DELIVERABLE','018f0000-0000-7000-8000-000000035614');
SELECT 'SELF_REVIEW='||service.review_deliverable('$DELIVERABLE','APPROVE','SELF_REVIEW_DENIED','018f0000-0000-7000-8000-000000035615');
SELECT 'WITHDRAWABLE='||service.create_versioned_deliverable('$WITHDRAWN_DELIVERABLE','$PROJECT','$PSUB','$DOCUMENT','$VERSION','SYNTHETIC_APPENDIX',clock_timestamp()+interval '10 days','018f0000-0000-7000-8000-000000035616');
SELECT 'WITHDRAWABLE_SUBMIT='||service.submit_deliverable('$WITHDRAWN_DELIVERABLE','018f0000-0000-7000-8000-000000035617');
SELECT 'MISMATCHED_VERSION='||service.create_versioned_deliverable('018f0000-0000-7000-8000-000000035435','$PROJECT','$PSUB','$OLD_DOCUMENT','$OLD_VERSION','WRONG_SUBJECT',NULL,'018f0000-0000-7000-8000-000000035618');
SQL
out="$(run_session "$SERVICE" "$FAMILY_A" 018f0000-0000-7000-8000-000000035701 /tmp/f10-0035-create.sql)"
for expected in PROJECT=true PLAN=true ACTIVE=true SUBJECT=true DOMAIN=true ASSIGN_SERVICE=true ASSIGN_REVIEWER=true TEMPLATE=true MILESTONE=true TASK=true TRANSFER=true TRANSFER_UNASSIGNED=false MILESTONE_ACHIEVED=true DOCUMENT=true VERSION=true DELIVERABLE=true SUBMIT=true SELF_REVIEW=false WITHDRAWABLE=true WITHDRAWABLE_SUBMIT=true MISMATCHED_VERSION=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0035-review-changes.sql <<SQL
SELECT 'TASK_START='||service.transition_task('$TASK','IN_PROGRESS','TRANSFERRED_WORK_STARTED','018f0000-0000-7000-8000-000000035619');
SELECT 'TASK_COMPLETE='||service.transition_task('$TASK','COMPLETED','TRANSFERRED_WORK_COMPLETED','018f0000-0000-7000-8000-000000035620');
SELECT 'REQUEST_CHANGES='||service.review_deliverable('$DELIVERABLE','REQUEST_CHANGES','SYNTHETIC_CHANGES_REQUIRED','018f0000-0000-7000-8000-000000035621');
SELECT 'WITHDRAW='||service.withdraw_deliverable('$WITHDRAWN_DELIVERABLE','SYNTHETIC_WITHDRAWAL','018f0000-0000-7000-8000-000000035622');
SQL
out="$(run_session "$REVIEWER" "$FAMILY_A" 018f0000-0000-7000-8000-000000035702 /tmp/f10-0035-review-changes.sql)"
for expected in TASK_START=true TASK_COMPLETE=true REQUEST_CHANGES=true WITHDRAW=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0035-resubmit.sql <<SQL
SELECT 'RESUBMIT='||service.submit_deliverable('$DELIVERABLE','018f0000-0000-7000-8000-000000035623');
SQL
out="$(run_session "$SERVICE" "$FAMILY_A" 018f0000-0000-7000-8000-000000035703 /tmp/f10-0035-resubmit.sql)"
expect_line 'RESUBMIT=true' "$out"

cat >/tmp/f10-0035-approve.sql <<SQL
SELECT 'APPROVE='||service.review_deliverable('$DELIVERABLE','APPROVE','SYNTHETIC_REVIEW_APPROVED','018f0000-0000-7000-8000-000000035624');
SELECT 'SELF_ACCEPT='||service.accept_deliverable('$DELIVERABLE','018f0000-0000-7000-8000-000000035625');
SQL
out="$(run_session "$REVIEWER" "$FAMILY_A" 018f0000-0000-7000-8000-000000035704 /tmp/f10-0035-approve.sql)"
expect_line 'APPROVE=true' "$out"; expect_line 'SELF_ACCEPT=false' "$out"

cat >/tmp/f10-0035-accept-close.sql <<SQL
SELECT 'ACCEPT='||service.accept_deliverable('$DELIVERABLE','018f0000-0000-7000-8000-000000035626');
SELECT 'RETIRE_TEMPLATE='||service.retire_milestone_template('$TEMPLATE');
SELECT 'RETIRED_TEMPLATE_REUSE='||service.create_milestone_from_template('018f0000-0000-7000-8000-000000035422','$PROJECT','$TEMPLATE','M5_RETIRED_REUSE',NULL,'018f0000-0000-7000-8000-000000035627');
SELECT 'PROJECT_COMPLETE='||service.transition_project('$PROJECT','COMPLETED','018f0000-0000-7000-8000-000000035628');
SQL
out="$(run_session "$SERVICE" "$FAMILY_A" 018f0000-0000-7000-8000-000000035705 /tmp/f10-0035-accept-close.sql)"
for expected in ACCEPT=true RETIRE_TEMPLATE=true RETIRED_TEMPLATE_REUSE=false PROJECT_COMPLETE=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0035-cross.sql <<SQL
SELECT 'CROSS_FAMILY='||service.create_versioned_deliverable('018f0000-0000-7000-8000-000000035436','$PROJECT','$PSUB','$DOCUMENT','$VERSION','CROSS_FAMILY',NULL,'018f0000-0000-7000-8000-000000035629');
SQL
out="$(run_session "$SERVICE" "$FAMILY_B" 018f0000-0000-7000-8000-000000035706 /tmp/f10-0035-cross.sql)"
expect_line 'CROSS_FAMILY=false' "$out"

shape="$(bootstrap_psql -Atqc "SELECT
  (SELECT assigned_principal_id FROM service.tasks WHERE task_id='$TASK')||'|'||
  (SELECT count(*) FROM service.task_events WHERE task_id='$TASK' AND event_kind='TRANSFERRED')||'|'||
  (SELECT status||':'||submission_round||':'||(document_version_id='$VERSION')::text FROM service.deliverables WHERE deliverable_id='$DELIVERABLE')||'|'||
  (SELECT status FROM service.deliverables WHERE deliverable_id='$WITHDRAWN_DELIVERABLE')||'|'||
  (SELECT count(*) FROM service.delivery_events WHERE deliverable_id='$DELIVERABLE')||'|'||
  (SELECT status FROM service.milestone_templates WHERE milestone_template_id='$TEMPLATE')")"
test "$shape" = "$REVIEWER|1|ACCEPTED:2:true|WITHDRAWN|6|RETIRED" || { echo "FAIL M5 shape=$shape" >&2; exit 1; }

event_mutation="$(bootstrap_psql -Atqc "UPDATE service.delivery_events SET reason_code='FORGED' WHERE deliverable_id='$DELIVERABLE'" 2>&1 || true)"
grep -q 'SERVICE_EVENT_IMMUTABLE' <<<"$event_mutation" || { echo "FAIL delivery event mutation=$event_mutation" >&2; exit 1; }
terminal_mutation="$(bootstrap_psql -Atqc "UPDATE service.deliverables SET status='DRAFT' WHERE deliverable_id='$DELIVERABLE'" 2>&1 || true)"
grep -q 'SERVICE_DELIVERABLE_TERMINAL' <<<"$terminal_mutation" || { echo "FAIL deliverable terminal mutation=$terminal_mutation" >&2; exit 1; }

content_columns="$(bootstrap_psql -Atqc "SELECT count(*) FROM information_schema.columns WHERE table_schema='service' AND column_name ~ '(body|content|payload|blob)'")"
test "$content_columns" = 0 || { echo "FAIL Service domain contains content-like columns=$content_columns" >&2; exit 1; }

acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','service.delivery_events','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','service.milestone_templates','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.create_deliverable(uuid,uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.transition_deliverable(uuid,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','service.create_versioned_deliverable(uuid,uuid,uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('public','service.review_deliverable(uuid,text,text,uuid)','EXECUTE')::text")"
test "$acl" = 'false|false|false|false|true|false' || { echo "FAIL M5 ACL=$acl" >&2; exit 1; }

echo 'PASS 0035 task transfer history, milestone templates, version-bound deliverables, split review/acceptance, withdrawal/resubmission, tenant isolation, immutability and exact ACL'
