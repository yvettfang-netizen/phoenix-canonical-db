#!/usr/bin/env bash
set -euo pipefail
umask 077

DB=phoenix_canonical_dev
APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
SERVICE_P=018f0000-0000-7000-8000-000000002001
GUARDIAN_P=018f0000-0000-7000-8000-000000002002
FAMILY_B_P=018f0000-0000-7000-8000-000000002006
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
GUARDIAN=018f0000-0000-7000-8000-000000001002
STUDENT=018f0000-0000-7000-8000-000000001003
TEACHER=018f0000-0000-7000-8000-000000012201
SUPERVISOR=018f0000-0000-7000-8000-000000012202
TEACHER_P=018f0000-0000-7000-8000-000000022201
SUPERVISOR_P=018f0000-0000-7000-8000-000000022202
COURSE=018f0000-0000-7000-8000-000000021101
VERSION=018f0000-0000-7000-8000-000000022211
CLASS=018f0000-0000-7000-8000-000000022221
ASSIGNMENT=018f0000-0000-7000-8000-000000022231
SLOT=018f0000-0000-7000-8000-000000022241
ENROLLMENT=018f0000-0000-7000-8000-000000022251
ATTENDANCE=018f0000-0000-7000-8000-000000022261
CARD=018f0000-0000-7000-8000-000000022271
REPORT=018f0000-0000-7000-8000-000000022281

app_psql() { local login="$1" pgpass="$2"; shift 2; PGPASSFILE="$pgpass" psql -X -qAt -h 127.0.0.1 -U "$login" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -qAt -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -qAt -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

make_login() {
  local login="$1" file="$2" secret
  secret="$(openssl rand -hex 32)"
  printf '127.0.0.1:5432:*:%s:%s\n' "$login" "$secret" > "$file"
  chmod 600 "$file"
  bootstrap_psql -c "CREATE ROLE $login LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$secret'; GRANT phoenix_canonical_app TO $login WITH INHERIT TRUE, SET FALSE; GRANT CONNECT ON DATABASE $DB TO $login;"
  unset secret
}

make_login phoenix_learning_service_f10 /tmp/f10-learning-service.pgpass
make_login phoenix_learning_teacher_f10 /tmp/f10-learning-teacher.pgpass
make_login phoenix_learning_supervisor_f10 /tmp/f10-learning-supervisor.pgpass
make_login phoenix_learning_family_f10 /tmp/f10-learning-family.pgpass

run_session() {
  local login="$1" pgpass="$2" principal="$3" actor="$4" family="$5" channel="$6" file="$7"
  local ticket actor_sql family_sql
  actor_sql=NULL; family_sql=NULL
  [ "$actor" = NULL ] || actor_sql="'$actor'::uuid"
  [ "$family" = NULL ] || family_sql="'$family'::uuid"
  ticket="$(binder_psql -c "SELECT auth.issue_context_ticket('$principal',$actor_sql,$family_sql,'$channel',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$principal')")"
  {
    printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql "$login" "$pgpass" -f -
}

echo 'TEST 0022 separate SERVICE, TEACHER, SUPERVISOR and FAMILY database LOGIN accounts with one-use tickets'

cat >/tmp/f10-0022-global.sql <<SQL
SELECT 'TEACHER_PERSON='||core.register_external_person('$TEACHER','Synthetic Learning Teacher');
SELECT 'SUPERVISOR_PERSON='||core.register_external_person('$SUPERVISOR','Synthetic Learning Supervisor');
SELECT 'TEACHER='||learning.register_teacher('$TEACHER');
SELECT 'TEACHER_PRINCIPAL='||learning.register_staff_principal('$TEACHER_P','$TEACHER','TEACHER');
SELECT 'SUPERVISOR_PRINCIPAL='||learning.register_staff_principal('$SUPERVISOR_P','$SUPERVISOR','SUPERVISOR');
SELECT 'COURSE='||learning.create_course('$COURSE','SYN-COURSE-0022','Synthetic Learning Course');
SELECT 'COURSE_PUBLISH='||learning.advance_course('$COURSE','PUBLISHED');
SELECT 'VERSION='||learning.create_course_version('$VERSION','$COURSE',1,clock_timestamp()-interval '1 day',clock_timestamp()+interval '30 days');
SELECT 'VERSION_ACTIVE='||learning.advance_course_version('$VERSION','ACTIVE');
SELECT 'CLASS='||learning.create_class('$CLASS','$VERSION','SYN-CLASS-0022',1,current_date,current_date+30);
SELECT 'CLASS_OPEN='||learning.advance_class('$CLASS','OPEN');
SELECT 'ASSIGN='||learning.assign_teacher('$ASSIGNMENT','$CLASS','$TEACHER','LEAD',clock_timestamp()-interval '1 hour',clock_timestamp()+interval '2 days');
SELECT 'SLOT='||learning.create_schedule_slot('$SLOT','$CLASS','$TEACHER',clock_timestamp()+interval '2 hours',clock_timestamp()+interval '3 hours','Synthetic Room');
SELECT 'OVERLAP='||learning.create_schedule_slot('018f0000-0000-7000-8000-000000022242','$CLASS','$TEACHER',clock_timestamp()+interval '2 hours 30 minutes',clock_timestamp()+interval '3 hours 30 minutes','Overlap Room');
SQL
global_out="$(run_session phoenix_learning_service_f10 /tmp/f10-learning-service.pgpass "$SERVICE_P" NULL NULL INTERNAL /tmp/f10-0022-global.sql)"
for expected in TEACHER_PERSON=true SUPERVISOR_PERSON=true TEACHER=true TEACHER_PRINCIPAL=true SUPERVISOR_PRINCIPAL=true COURSE=true COURSE_PUBLISH=true VERSION=true VERSION_ACTIVE=true CLASS=true CLASS_OPEN=true ASSIGN=true SLOT=true OVERLAP=false; do expect_line "$expected" "$global_out"; done

cat >/tmp/f10-0022-family-service.sql <<SQL
SELECT 'GUARDIAN_SCOPE='||core.create_guardian_authority('018f0000-0000-7000-8000-000000022291','$FAMILY_A','$GUARDIAN','$STUDENT','VERIFIED','LEARNING',clock_timestamp()+interval '2 days','synthetic/evidence/learning');
SQL
family_service_out="$(run_session phoenix_learning_service_f10 /tmp/f10-learning-service.pgpass "$SERVICE_P" NULL "$FAMILY_A" INTERNAL /tmp/f10-0022-family-service.sql)"
expect_line 'GUARDIAN_SCOPE=true' "$family_service_out"

cat >/tmp/f10-0022-consent.sql <<SQL
SELECT 'TEACHER_CONSENT='||consent.create_grant('018f0000-0000-7000-8000-000000022301','$FAMILY_A','$TEACHER','$STUDENT','LEARNING_RECORD','LEARNING',clock_timestamp()+interval '2 days');
SELECT 'SUPERVISOR_CONSENT='||consent.create_grant('018f0000-0000-7000-8000-000000022302','$FAMILY_A','$SUPERVISOR','$STUDENT','LEARNING_RECORD','LEARNING',clock_timestamp()+interval '2 days');
SELECT 'GUARDIAN_CONSENT='||consent.create_grant('018f0000-0000-7000-8000-000000022303','$FAMILY_A','$GUARDIAN','$STUDENT','LEARNING_RECORD','LEARNING',clock_timestamp()+interval '2 days');
SQL
consent_out="$(run_session phoenix_learning_family_f10 /tmp/f10-learning-family.pgpass "$GUARDIAN_P" "$GUARDIAN" "$FAMILY_A" FAMILY /tmp/f10-0022-consent.sql)"
for expected in TEACHER_CONSENT=true SUPERVISOR_CONSENT=true GUARDIAN_CONSENT=true; do expect_line "$expected" "$consent_out"; done

consent_before="$(bootstrap_psql -c "SELECT count(*) FROM consent.grants WHERE family_id='$FAMILY_A' AND subject_person_id='$STUDENT' AND purpose='LEARNING_RECORD'")"
cat >/tmp/f10-0022-enroll.sql <<SQL
SELECT 'ENROLL='||learning.create_enrollment('$ENROLLMENT','018f0000-0000-7000-8000-000000022311','$FAMILY_A','$STUDENT','$VERSION','ENTITLEMENT_ACCEPTED');
SELECT 'ACTIVATE='||learning.advance_enrollment('$ENROLLMENT','018f0000-0000-7000-8000-000000022312','ACTIVE','CONSENT_READY');
SELECT 'PLACE='||learning.place_enrollment_in_class('$ENROLLMENT','$CLASS');
SQL
enroll_out="$(run_session phoenix_learning_service_f10 /tmp/f10-learning-service.pgpass "$SERVICE_P" NULL "$FAMILY_A" INTERNAL /tmp/f10-0022-enroll.sql)"
for expected in ENROLL=true ACTIVATE=true PLACE=true; do expect_line "$expected" "$enroll_out"; done
consent_after="$(bootstrap_psql -c "SELECT count(*) FROM consent.grants WHERE family_id='$FAMILY_A' AND subject_person_id='$STUDENT' AND purpose='LEARNING_RECORD'")"
[ "$consent_before" = "$consent_after" ] || { echo 'FAIL enrollment created Consent'; exit 1; }
echo 'PASS entitlement permits enrollment but creates no Consent'

cat >/tmp/f10-0022-teacher.sql <<SQL
SELECT 'ATTENDANCE='||learning.record_attendance('$ATTENDANCE','$SLOT','$ENROLLMENT','PRESENT');
SELECT 'CARD='||learning.save_after_class_card('$CARD','$SLOT','$ENROLLMENT','Synthetic progress summary');
SELECT 'CARD_SUBMIT='||learning.submit_after_class_card('$CARD');
SELECT 'TEACHER_PUBLISH='||learning.publish_after_class_card('018f0000-0000-7000-8000-000000022321','$CARD');
SELECT 'REPORT='||learning.save_stage_report('$REPORT','$ENROLLMENT','Synthetic Period','Synthetic stage summary');
SELECT 'REPORT_SUBMIT='||learning.advance_stage_report('$REPORT','SUBMITTED');
SQL
teacher_out="$(run_session phoenix_learning_teacher_f10 /tmp/f10-learning-teacher.pgpass "$TEACHER_P" "$TEACHER" "$FAMILY_A" STAFF /tmp/f10-0022-teacher.sql)"
for expected in ATTENDANCE=true CARD=true CARD_SUBMIT=true TEACHER_PUBLISH=false REPORT=true REPORT_SUBMIT=true; do expect_line "$expected" "$teacher_out"; done

cat >/tmp/f10-0022-supervisor.sql <<SQL
SELECT 'PUBLISH='||learning.publish_after_class_card('018f0000-0000-7000-8000-000000022322','$CARD');
SELECT 'REPORT_PUBLISH='||learning.advance_stage_report('$REPORT','PUBLISHED');
SQL
supervisor_out="$(run_session phoenix_learning_supervisor_f10 /tmp/f10-learning-supervisor.pgpass "$SUPERVISOR_P" "$SUPERVISOR" "$FAMILY_A" STAFF /tmp/f10-0022-supervisor.sql)"
for expected in PUBLISH=true REPORT_PUBLISH=true; do expect_line "$expected" "$supervisor_out"; done

cat >/tmp/f10-0022-family-read.sql <<SQL
SELECT 'CARD_READ='||count(*) FROM learning.read_published_card('$CARD');
SELECT 'REPORT_READ='||count(*) FROM learning.read_published_stage_report('$REPORT');
SQL
family_read="$(run_session phoenix_learning_family_f10 /tmp/f10-learning-family.pgpass "$GUARDIAN_P" "$GUARDIAN" "$FAMILY_A" FAMILY /tmp/f10-0022-family-read.sql)"
expect_line 'CARD_READ=1' "$family_read"; expect_line 'REPORT_READ=1' "$family_read"

teacher_read="$(run_session phoenix_learning_teacher_f10 /tmp/f10-learning-teacher.pgpass "$TEACHER_P" "$TEACHER" "$FAMILY_A" STAFF /tmp/f10-0022-family-read.sql)"
expect_line 'CARD_READ=1' "$teacher_read"; expect_line 'REPORT_READ=1' "$teacher_read"

cross_read="$(run_session "$APP" /tmp/f10-app.pgpass "$FAMILY_B_P" '018f0000-0000-7000-8000-000000001006' "$FAMILY_B" FAMILY /tmp/f10-0022-family-read.sql)"
expect_line 'CARD_READ=0' "$cross_read"; expect_line 'REPORT_READ=0' "$cross_read"

if binder_psql -c "SELECT auth.issue_context_ticket('$TEACHER_P','$TEACHER','$FAMILY_A','FAMILY',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$TEACHER_P')" >/tmp/f10-0022-kind.out 2>&1; then
  echo 'FAIL TEACHER principal accepted FAMILY channel' >&2; exit 1
fi
grep -q 'CONTEXT_PRINCIPAL_CHANNEL_MISMATCH' /tmp/f10-0022-kind.out
echo 'PASS TEACHER principal rejected on non-STAFF channel'

if app_psql phoenix_learning_teacher_f10 /tmp/f10-learning-teacher.pgpass -c 'SELECT count(*) FROM learning.after_class_card' >/tmp/f10-0022-direct.out 2>&1; then
  echo 'FAIL TEACHER login directly read Learning table' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0022-direct.out

cat >/tmp/f10-0022-withdraw.sql <<SQL
SELECT 'WITHDRAW='||consent.withdraw_grant('018f0000-0000-7000-8000-000000022301');
SQL
withdraw_out="$(run_session phoenix_learning_family_f10 /tmp/f10-learning-family.pgpass "$GUARDIAN_P" "$GUARDIAN" "$FAMILY_A" FAMILY /tmp/f10-0022-withdraw.sql)"
expect_line 'WITHDRAW=true' "$withdraw_out"
teacher_after_withdraw="$(run_session phoenix_learning_teacher_f10 /tmp/f10-learning-teacher.pgpass "$TEACHER_P" "$TEACHER" "$FAMILY_A" STAFF /tmp/f10-0022-family-read.sql)"
expect_line 'CARD_READ=0' "$teacher_after_withdraw"; expect_line 'REPORT_READ=0' "$teacher_after_withdraw"

cat >/tmp/f10-0022-finish.sql <<SQL
SELECT 'END_ASSIGNMENT='||learning.end_teacher_assignment('$ASSIGNMENT',true);
SELECT 'COMPLETE_ENROLLMENT='||learning.advance_enrollment('$ENROLLMENT','018f0000-0000-7000-8000-000000022313','COMPLETED','COURSE_COMPLETE');
SQL
finish_out="$(run_session phoenix_learning_service_f10 /tmp/f10-learning-service.pgpass "$SERVICE_P" NULL "$FAMILY_A" INTERNAL /tmp/f10-0022-finish.sql)"
expect_line 'END_ASSIGNMENT=true' "$finish_out"; expect_line 'COMPLETE_ENROLLMENT=true' "$finish_out"

cat >/tmp/f10-0022-retract.sql <<SQL
SELECT 'RETRACT='||learning.retract_after_class_card('018f0000-0000-7000-8000-000000022323','$CARD');
SELECT 'REPORT_RETRACT='||learning.advance_stage_report('$REPORT','RETRACTED');
SQL
retract_out="$(run_session phoenix_learning_supervisor_f10 /tmp/f10-learning-supervisor.pgpass "$SUPERVISOR_P" "$SUPERVISOR" "$FAMILY_A" STAFF /tmp/f10-0022-retract.sql)"
expect_line 'RETRACT=true' "$retract_out"; expect_line 'REPORT_RETRACT=true' "$retract_out"
family_after_retract="$(run_session phoenix_learning_family_f10 /tmp/f10-learning-family.pgpass "$GUARDIAN_P" "$GUARDIAN" "$FAMILY_A" FAMILY /tmp/f10-0022-family-read.sql)"
expect_line 'CARD_READ=0' "$family_after_retract"; expect_line 'REPORT_READ=0' "$family_after_retract"

if bootstrap_psql -c "UPDATE learning.enrollment SET status='ACTIVE' WHERE enrollment_id='$ENROLLMENT'" >/tmp/f10-0022-terminal.out 2>&1; then
  echo 'FAIL terminal enrollment reactivated' >&2; exit 1
fi
grep -q 'LEARNING_STATE_TRANSITION_INVALID' /tmp/f10-0022-terminal.out
if bootstrap_psql -c "UPDATE learning.publication SET event_kind='RETRACTED' WHERE publication_id='018f0000-0000-7000-8000-000000022322'" >/tmp/f10-0022-history.out 2>&1; then
  echo 'FAIL publication history mutated' >&2; exit 1
fi
grep -q 'LEARNING_HISTORY_IMMUTABLE' /tmp/f10-0022-history.out

catalog="$(bootstrap_psql -c "SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname='learning'; SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname='learning'; SELECT 'audit_allow='||count(*) FROM audit.access_events WHERE resource_kind LIKE 'LEARNING_%' AND decision='ALLOW'; SELECT 'audit_deny='||count(*) FROM audit.access_events WHERE resource_kind LIKE 'LEARNING_%' AND decision='DENY';")"
expect_line 'tables=14' "$catalog"; expect_line 'policies=14' "$catalog"
grep -q '^audit_allow=[1-9]' <<<"$catalog"; grep -q '^audit_deny=[1-9]' <<<"$catalog"

acl="$(bootstrap_psql -c "SELECT (NOT has_table_privilege('phoenix_canonical_app','learning.after_class_card','SELECT') AND NOT has_table_privilege('phoenix_canonical_app','learning.enrollment','INSERT') AND NOT has_function_privilege('public','learning.can_read_sensitive(uuid,uuid,uuid)','EXECUTE') AND has_function_privilege('phoenix_canonical_app','learning.read_published_card(uuid)','EXECUTE'))")"
[ "$acl" = t ] || { echo 'FAIL Learning ACL boundary'; exit 1; }

echo 'PASS 0022 Learning identity, Consent, entitlement, assignment, schedule, attendance, publication, tenant, audit, terminal-history and ACL regression'
