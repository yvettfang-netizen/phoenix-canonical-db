#!/usr/bin/env bash
# Claude V1.6 closeout probes (run inside the disposable F10 container after the Codex suites).
# Observation probes: each prints OBSERVED lines; expectations follow the approved contracts.
set -uo pipefail
app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap           -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001
SVC_P=018f0000-0000-7000-8000-000000002001
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004
G=018f0000-0000-7000-8000-000000001002; STU=018f0000-0000-7000-8000-000000001003
APP=018f0000-0000-7000-8000-000000004001; CASE_APP=018f0000-0000-7000-8000-000000004011
CASE_ID=018f0000-0000-7000-8000-000000004012
fail=0
service() { # SQL on stdin, INTERNAL bound to family A
  local t; t="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$SVC_P',NULL,'$FA','INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$SVC_P')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$SVC_P"; cat; printf "SELECT auth.clear_context();\n"; } | app_psql -At -f - 2>&1 | grep -E '^[A-Z][A-Z0-9_]*=|ERROR'
}
advisor() {
  local t; t="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$ADV_P','$ADV','$FA','ADVISOR',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$ADV_P')" 2>&1)" || { echo "TICKET_ERROR $(grep -o 'ERROR:.*' <<<"$t")"; return 0; }
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$ADV_P"; cat; printf "SELECT auth.clear_context();\n"; } | app_psql -At -f - 2>&1 | grep -E '^[A-Z][A-Z0-9_]*=|ERROR'
}
val() { grep -m1 "^$1=" <<<"$2" | cut -d= -f2; }
expect() { if [ "$2" = "$3" ]; then echo "PASS $1 ($2)"; else echo "FINDING $1 got=[$2] expected=[$3]"; fail=1; fi; }

echo "=== P1 closed case must end the advisor's write authority over its resource (EV-1 8.1 / BC: active case assignment)"
echo "state: case 4011 status=$(bootstrap_psql -Atqc "SELECT status FROM casework.cases WHERE case_id='$CASE_APP'") ; other open cases for advisor in family A=$(bootstrap_psql -Atqc "SELECT count(*) FROM casework.cases c JOIN casework.advisor_assignments a ON a.case_id=c.case_id WHERE c.family_id='$FA' AND a.advisor_person_id='$ADV' AND c.status IN ('OPEN','PAUSED') AND c.case_id<>'$CASE_APP'")"
out="$(advisor <<SQL
SELECT 'CONTROL='||education.record_external_fact('018f0000-0000-7000-8000-00000000b001','$APP','OFFICIAL_RECEIPT','Synthetic Source','SYN-P1-CONTROL',clock_timestamp()-interval '1 hour');
SQL
)"; printf '%s\n' "$out"
expect 'P1 control: advisor may record a fact while case 4011 is open' "$(val CONTROL "$out")" true
out="$(service <<SQL
SELECT 'CLOSE='||casework.close_case('$CASE_APP');
SQL
)"; printf '%s\n' "$out"
expect 'P1 setup: service closes case 4011' "$(val CLOSE "$out")" true
out="$(advisor <<SQL
SELECT 'AFTER_CLOSE='||education.record_external_fact('018f0000-0000-7000-8000-00000000b002','$APP','OFFICIAL_RECEIPT','Synthetic Source','SYN-P1-AFTER',clock_timestamp()-interval '1 hour');
SQL
)"; printf '%s\n' "$out"
expect 'P1 advisor fact on closed case resource denied' "$(val AFTER_CLOSE "$out")" false

echo "=== P2 duplicate active assignment returns an audited denial instead of an exception"
out="$(service <<SQL
SELECT 'DUP='||casework.create_advisor_assignment('018f0000-0000-7000-8000-00000000b003','$CASE_ID','$ADV',clock_timestamp()+interval '1 day');
SQL
)"; printf '%s\n' "$out"
dup="$(val DUP "$out")"; [ -z "$dup" ] && dup="EXCEPTION:$(grep -o 'ERROR:.*' <<<"$out" | head -1 | cut -c1-90)"
expect 'P2 duplicate active assignment' "$dup" false

echo "=== P3 case subject must match the referenced resource's subject (EV-4 1.2 integrity)"
out="$(service <<SQL
SELECT 'MISMATCH='||casework.create_case('018f0000-0000-7000-8000-00000000b004','$FA','$G','Synthetic mismatched subject','EDUCATION_APPLICATION','$APP');
SQL
)"; printf '%s\n' "$out"
expect 'P3 case on guardian referencing the student application' "$(val MISMATCH "$out")" false

[ "$fail" = 0 ] && echo "PASS Claude V1.6 probes" || echo "FINDINGS Claude V1.6 probes (see FINDING lines)"
exit 0
