#!/usr/bin/env bash
# V1.7 / 0016 permanent regression: advisor authority follows an ACTIVE assignment
# on an OPEN or PAUSED case whose resource belongs to the case's family and
# subject; duplicate active assignments and guardian authorities are audited
# denials. Synthetic IDs only; separate LOGINs and one-use tickets.
set -euo pipefail
app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap           -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001
SVC_P=018f0000-0000-7000-8000-000000002001
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004
G=018f0000-0000-7000-8000-000000001002; STU=018f0000-0000-7000-8000-000000001003
C1=018f0000-0000-7000-8000-00000000c001; C2=018f0000-0000-7000-8000-00000000c002; C3=018f0000-0000-7000-8000-00000000c003
A1=018f0000-0000-7000-8000-00000000c011; A2=018f0000-0000-7000-8000-00000000c012; A3=018f0000-0000-7000-8000-00000000c013
APPX=018f0000-0000-7000-8000-00000000c021; APPY=018f0000-0000-7000-8000-00000000c022
F1=018f0000-0000-7000-8000-00000000c031; F2=018f0000-0000-7000-8000-00000000c032
GA1=018f0000-0000-7000-8000-00000000c041; GA2=018f0000-0000-7000-8000-00000000c042

session() { # principal actor(NULL for service) channel ; SQL on stdin ; prints KEY=value and ERROR lines
  local actor_sql=NULL ticket
  [ "$2" != NULL ] && actor_sql="'$2'"
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$1',$actor_sql,'$FA','$3',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$1"; cat; printf "SELECT auth.clear_context();\n"; } \
    | app_psql -At -f - 2>&1 | grep -E '^[A-Z][A-Z0-9_]*=|ERROR' || true
}
val()    { grep -m1 "^$1=" <<<"$2" | cut -d= -f2; }
check()  { [ "$2" = "$3" ] && echo "PASS $1=$2" || { echo "FAIL $1 got=[$2] expected=[$3]"; exit 1; }; }
reason() { bootstrap_psql -Atqc "SELECT reason_code FROM audit.access_events WHERE resource_id='$1' AND action='$2' ORDER BY event_id DESC LIMIT 1"; }

# Service: pre-allocated case for a not-yet-created application (EV-4 E4-6), one assignment, duplicate denials.
out="$(session $SVC_P NULL INTERNAL <<SQL
SELECT 'CASE_C1='||casework.create_case('$C1','$FA','$STU','V17 scope case','EDUCATION_APPLICATION','$APPX');
SELECT 'ASSIGN_A1='||casework.create_advisor_assignment('$A1','$C1','$ADV',clock_timestamp()+interval '1 day');
SELECT 'ASSIGN_DUP='||casework.create_advisor_assignment('$A2','$C1','$ADV',clock_timestamp()+interval '1 day');
SELECT 'GUARD_FIRST='||core.create_guardian_authority('$GA1','$FA','$STU','$G','VERIFIED','IDENTITY',clock_timestamp()+interval '1 day','synthetic/evidence/v17');
SELECT 'GUARD_DUP='||core.create_guardian_authority('$GA2','$FA','$STU','$G','VERIFIED','IDENTITY',clock_timestamp()+interval '1 day','synthetic/evidence/v17-dup');
SQL
)"
check CASE_C1 "$(val CASE_C1 "$out")" true
check ASSIGN_A1 "$(val ASSIGN_A1 "$out")" true
check ASSIGN_DUP "$(val ASSIGN_DUP "$out")" false
check ASSIGN_DUP_REASON "$(reason $A2 ASSIGN)" ALREADY_ACTIVE
check GUARD_FIRST "$(val GUARD_FIRST "$out")" true
check GUARD_DUP "$(val GUARD_DUP "$out")" false
check GUARD_DUP_REASON "$(reason $GA2 VERIFY)" ALREADY_ACTIVE

# Advisor: creates the application through the pre-allocated case, records a fact, can read it.
out="$(session $ADV_P $ADV ADVISOR <<SQL
SELECT 'APPX_CREATE='||education.create_application('$APPX','$FA','$STU','Synthetic Institution','Synthetic Programme','2030');
SELECT 'FACT_OPEN='||education.record_external_fact('$F1','$APPX','OFFICIAL_RECEIPT','Synthetic Source','SYN-V17-OPEN',clock_timestamp()-interval '1 hour');
SELECT 'READ_OPEN='||count(*) FROM education.applications WHERE application_id='$APPX';
SQL
)"
check APPX_CREATE "$(val APPX_CREATE "$out")" true
check FACT_OPEN "$(val FACT_OPEN "$out")" true
check READ_OPEN "$(val READ_OPEN "$out")" 1

# Service: an existing resource of another subject cannot be referenced; a pre-allocated case on the
# guardian (resource not yet created) keeps the advisor bindable; then case C1 is closed.
out="$(session $SVC_P NULL INTERNAL <<SQL
SELECT 'CASE_MISMATCH='||casework.create_case('$C2','$FA','$G','V17 mismatched subject','EDUCATION_APPLICATION','$APPX');
SELECT 'CASE_C3='||casework.create_case('$C3','$FA','$G','V17 pre-allocated mismatch','EDUCATION_APPLICATION','$APPY');
SELECT 'ASSIGN_A3='||casework.create_advisor_assignment('$A3','$C3','$ADV',clock_timestamp()+interval '1 day');
SELECT 'CLOSE_C1='||casework.close_case('$C1');
SQL
)"
check CASE_MISMATCH "$(val CASE_MISMATCH "$out")" false
check CASE_MISMATCH_REASON "$(reason $C2 CREATE)" RESOURCE_FAMILY_OR_SUBJECT_MISMATCH
check CASE_C3 "$(val CASE_C3 "$out")" true
check ASSIGN_A3 "$(val ASSIGN_A3 "$out")" true
check CLOSE_C1 "$(val CLOSE_C1 "$out")" true

# Advisor (still bound through other open cases): no write or read authority over the closed case's resource.
out="$(session $ADV_P $ADV ADVISOR <<SQL
SELECT 'FACT_CLOSED='||education.record_external_fact('$F2','$APPX','OFFICIAL_RECEIPT','Synthetic Source','SYN-V17-CLOSED',clock_timestamp()-interval '1 hour');
SELECT 'ADVANCE_CLOSED='||education.advance_application('$APPX','READY');
SELECT 'READ_CLOSED='||count(*) FROM education.applications WHERE application_id='$APPX';
SQL
)"
check FACT_CLOSED "$(val FACT_CLOSED "$out")" false
check ADVANCE_CLOSED "$(val ADVANCE_CLOSED "$out")" false
check READ_CLOSED "$(val READ_CLOSED "$out")" 0
check FACT_CLOSED_ROWS "$(bootstrap_psql -Atqc "SELECT count(*) FROM education.external_facts WHERE fact_id='$F2'")" 0

# The advisor tries to create the student's application through the guardian's pre-allocated case.
out="$(session $ADV_P $ADV ADVISOR <<SQL
SELECT 'APPY_CREATE='||education.create_application('$APPY','$FA','$STU','Synthetic Institution','Synthetic Programme','2030');
SQL
)"
grep -q 'CASE_RESOURCE_FAMILY_OR_SUBJECT_MISMATCH' <<<"$out" && echo "PASS APPY_CREATE refused CASE_RESOURCE_FAMILY_OR_SUBJECT_MISMATCH" || { echo "FAIL APPY_CREATE got=[$out]"; exit 1; }
check APPY_ROWS "$(bootstrap_psql -Atqc "SELECT count(*) FROM education.applications WHERE application_id='$APPY'")" 0

echo 'PASS V1.7 assignment scope: closed case and subject mismatch remove advisor authority; duplicate grants are audited denials'
