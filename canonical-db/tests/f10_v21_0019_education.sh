#!/usr/bin/env bash
set -euo pipefail
umask 077

app_psql() { PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }

FA=018f0000-0000-7000-8000-000000000001
FB=018f0000-0000-7000-8000-000000000002
SVC_P=018f0000-0000-7000-8000-000000002001
G_P=018f0000-0000-7000-8000-000000002002; G=018f0000-0000-7000-8000-000000001002
STU=018f0000-0000-7000-8000-000000001003
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004
FB_P=018f0000-0000-7000-8000-000000002006; FB_ACTOR=018f0000-0000-7000-8000-000000001006
INST_DRAFT=018f0000-0000-7000-8000-000000019001
PROG_DRAFT=018f0000-0000-7000-8000-000000019002
INST_ACTIVE=018f0000-0000-7000-8000-000000019011
PROG_ACTIVE=018f0000-0000-7000-8000-000000019012
ACADEMIC=018f0000-0000-7000-8000-000000019021
ACADEMIC_BAD=018f0000-0000-7000-8000-000000019022
SCORE=018f0000-0000-7000-8000-000000019023
SCORE_ADV=018f0000-0000-7000-8000-000000019024
LANGUAGE=018f0000-0000-7000-8000-000000019025
PLAN=018f0000-0000-7000-8000-000000019026
APP=018f0000-0000-7000-8000-000000004001
DOC_OK=018f0000-0000-7000-8000-000000006001
DOC_OTHER=018f0000-0000-7000-8000-00000000b501

session() {
  local principal="$1" actor="$2" family="$3" channel="$4" ticket actor_sql="'$2'::uuid" family_sql="'$3'::uuid"
  [ "$actor" = NULL ] && actor_sql=NULL
  [ "$family" = NULL ] && family_sql=NULL
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',$actor_sql,$family_sql,'$channel',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$principal')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"; cat; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL expected [%s] in:\n%s\n' "$1" "$2"; exit 1; }; echo "PASS $1"; }

echo 'TEST 0019 Education with separated binder/app LOGIN accounts and one-use tickets'

out="$(session "$SVC_P" NULL NULL INTERNAL <<SQL
SELECT 'DRAFT_INST='||education.create_institution_draft('$INST_DRAFT','Synthetic Draft University','GB',1);
SELECT 'DRAFT_PROG='||education.create_program_draft('$PROG_DRAFT','$INST_DRAFT','Synthetic Draft Programme','MASTER',1);
SQL
)"
expect_line 'DRAFT_INST=true' "$out"
expect_line 'DRAFT_PROG=true' "$out"

bootstrap_psql <<SQL
INSERT INTO education.institution(institution_id,name,country_code,status,version,created_by_principal_id)
VALUES ('$INST_ACTIVE','Synthetic Active University','US','ACTIVE',1,'$SVC_P');
INSERT INTO education.program(program_id,institution_id,name,level,status,version,created_by_principal_id)
VALUES ('$PROG_ACTIVE','$INST_ACTIVE','Synthetic Active Programme','BACHELOR','ACTIVE',1,'$SVC_P');
SQL

out="$(session "$G_P" "$G" "$FA" FAMILY <<SQL
SELECT 'MASTER_ACTIVE='||count(*) FROM education.institution WHERE institution_id='$INST_ACTIVE';
SELECT 'MASTER_DRAFT='||count(*) FROM education.institution WHERE institution_id='$INST_DRAFT';
SELECT 'ACADEMIC='||education.create_academic_record('$ACADEMIC','$FA','$STU','SECONDARY','Synthetic School','2026-06-30','$DOC_OK');
SELECT 'ACADEMIC_WRONG_DOC='||education.create_academic_record('$ACADEMIC_BAD','$FA','$STU','SECONDARY','Synthetic School','2026-06-30','$DOC_OTHER');
SELECT 'SCORE='||education.create_score_record('$SCORE','$FA','$STU','Mathematics',91.5,'2026-05-01','Synthetic Exam Board');
SELECT 'LANGUAGE='||education.create_language_test('$LANGUAGE','$FA','$STU','IELTS','{"overall":7.5}'::jsonb,'2026-05-02','$DOC_OK');
SELECT 'PLAN='||education.create_plan('$PLAN','$FA','$STU','Synthetic education planning goal');
SELECT 'TARGET='||education.add_plan_target('$PLAN',1,'$INST_ACTIVE','$PROG_ACTIVE');
SELECT 'APP_TARGET='||education.set_application_master_target('$APP','$INST_ACTIVE','$PROG_ACTIVE');
SELECT 'APP_TARGET_MISSING='||education.set_application_master_target('$APP','018f0000-0000-7000-8000-000000019099',NULL);
SELECT 'ACADEMIC_VISIBLE='||count(*) FROM education.academic_record WHERE academic_record_id='$ACADEMIC';
SQL
)"
for line in MASTER_ACTIVE=1 MASTER_DRAFT=0 ACADEMIC=true ACADEMIC_WRONG_DOC=false SCORE=true LANGUAGE=true PLAN=true TARGET=true APP_TARGET=true APP_TARGET_MISSING=false ACADEMIC_VISIBLE=1; do expect_line "$line" "$out"; done

out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'ADVISOR_READ='||count(*) FROM education.academic_record WHERE academic_record_id='$ACADEMIC';
SELECT 'ADVISOR_WRITE='||education.create_score_record('$SCORE_ADV','$FA','$STU','Physics',88,'2026-05-03','Synthetic Advisor Entry');
SQL
)"
expect_line 'ADVISOR_READ=1' "$out"
expect_line 'ADVISOR_WRITE=true' "$out"

out="$(session "$FB_P" "$FB_ACTOR" "$FB" FAMILY <<SQL
SELECT 'CROSS_READ='||count(*) FROM education.academic_record WHERE academic_record_id='$ACADEMIC';
SELECT 'CROSS_WRITE='||education.create_score_record('018f0000-0000-7000-8000-000000019091','$FA','$STU','Forbidden',1,'2026-05-04','Cross family');
SQL
)"
expect_line 'CROSS_READ=0' "$out"
expect_line 'CROSS_WRITE=false' "$out"

if out="$(bootstrap_psql -Atqc "UPDATE education.institution SET name='Forbidden overwrite' WHERE institution_id='$INST_ACTIVE'" 2>&1)"; then
  echo 'FAIL master version was overwritten' >&2; exit 1
fi
grep -q 'EDUCATION_RECORD_APPEND_ONLY' <<<"$out" || { printf '%s\n' "$out" >&2; exit 1; }
echo 'PASS institution version update rejected'

if out="$(app_psql -Atqc "INSERT INTO education.score_record(score_record_id,family_id,student_person_id,subject,score,exam_date,source,recorded_by_principal_id) VALUES ('018f0000-0000-7000-8000-000000019092','$FA','$STU','Forbidden',1,current_date,'Direct','$G_P')" 2>&1)"; then
  echo 'FAIL app direct education write succeeded' >&2; exit 1
fi
grep -q 'permission denied' <<<"$out" || { printf '%s\n' "$out" >&2; exit 1; }
echo 'PASS app direct education table write denied'

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'SERVICE_RLS_READ='||count(*) FROM education.academic_record WHERE academic_record_id='$ACADEMIC';
SELECT 'SERVICE_WRITE='||education.create_score_record('018f0000-0000-7000-8000-000000019093','$FA','$STU','Chemistry',86,'2026-05-05','Synthetic Service Entry');
SQL
)"
expect_line 'SERVICE_RLS_READ=0' "$out"
expect_line 'SERVICE_WRITE=true' "$out"

echo 'PASS 0019/0020 Education master, evidence, tenant RLS, advisor Consent, SERVICE write-only and write API regression'

