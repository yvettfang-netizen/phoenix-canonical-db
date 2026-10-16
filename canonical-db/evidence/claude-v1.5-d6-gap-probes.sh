#!/usr/bin/env bash
# Claude V1.4 independent D-12/D-13/D-14 probes for gaps not asserted by the Codex suite.
# Runs inside the disposable F10 container after seed + regression. Synthetic IDs only.
set -uo pipefail
app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap           -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001
G_P=018f0000-0000-7000-8000-000000002002;   G=018f0000-0000-7000-8000-000000001002     # guardian, FAMILY
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004   # advisor
SVC_P=018f0000-0000-7000-8000-000000002001; SVC=018f0000-0000-7000-8000-000000001001   # service, INTERNAL
STU=018f0000-0000-7000-8000-000000001003
APP=018f0000-0000-7000-8000-00000000a001   # fresh application created below (4003 is WITHDRAWN by the Codex suite)
VER=018f0000-0000-7000-8000-000000006101
M=018f0000-0000-7000-8000-00000000a002
FACT_FAM=018f0000-0000-7000-8000-00000000a003
FACT_SVC=018f0000-0000-7000-8000-00000000a004
fail=0

session() { # principal actor channel ; SQL on stdin
  local t
  t="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$1','$2','$FA','$3',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')" 2>&1)" || { echo "TICKET_ERROR $3 $(grep -o 'ERROR:.*' <<<"$t" | head -1)"; return 0; }
  { printf "SELECT auth.redeem_context_ticket('%s'::uuid,'%s'::uuid);\n" "$t" "$1"; cat; printf "SELECT auth.clear_context();\n"; } \
    | app_psql -At -f - 2>&1 | grep -E '^[A-Z][A-Z0-9]*=|ERROR'
}
val()    { grep -m1 "^$1=" <<<"$2" | cut -d= -f2; }
reason() { bootstrap_psql -Atqc "SELECT reason_code FROM audit.access_events WHERE resource_id='$1' AND action='$2' ORDER BY event_id DESC LIMIT 1"; }
expect() { if [ "$2" = "$3" ]; then echo "PASS $1 ($2)"; else echo "FAIL $1 got=[$2] expected=[$3]"; fail=1; fi; }

echo "=== setup (guardian FAMILY): new application + manifest, one pinned item; family tries to record an official fact"
out="$(session $G_P $G FAMILY <<SQL
SELECT 'S0='||education.create_application('$APP','$FA','$STU','Synthetic Institution','Synthetic Programme','2029');
SELECT 'S1='||docs.create_submission_manifest('$M','$FA','$STU','EDUCATION_APPLICATION','$APP');
SELECT 'S2='||docs.add_submission_item('$M',1,'$VER');
SELECT 'G2='||education.record_external_fact('$FACT_FAM','$APP','DECISION','Synthetic Institution','SYN-REF-FAM',clock_timestamp()-interval '1 hour');
SELECT 'S4='||education.advance_application('$APP','READY');
SELECT 'S5='||education.advance_application('$APP','SUBMITTED');
SQL
)"; printf '%s\n' "$out"
expect 'setup application created' "$(val S0 "$out")" true
expect 'setup manifest created' "$(val S1 "$out")" true
expect 'setup item pinned' "$(val S2 "$out")" true
expect 'G2 family records official DECISION fact denied' "$(val G2 "$out")" false
expect 'G2 audit reason' "$(reason $FACT_FAM RECORD)" OFFICIAL_FACT_AUTHORITY_OR_INPUT_DENIED
expect 'setup application READY' "$(val S4 "$out")" true
expect 'setup application SUBMITTED' "$(val S5 "$out")" true

echo "=== G5 advisor (non-family side) confirms manifest"
out="$(session $ADV_P $ADV ADVISOR <<SQL
SELECT 'G5='||docs.confirm_manifest('$M');
SQL
)"; printf '%s\n' "$out"
expect 'G5 advisor confirmation denied' "$(val G5 "$out")" false
expect 'G5 audit reason' "$(reason $M CONFIRM)" FAMILY_AUTHORITY_OR_STATE_DENIED

echo "=== guardian confirms, then G4 tries to add an item through the API"
out="$(session $G_P $G FAMILY <<SQL
SELECT 'S3='||docs.confirm_manifest('$M');
SELECT 'G4='||docs.add_submission_item('$M',2,'$VER');
SQL
)"; printf '%s\n' "$out"
expect 'setup guardian confirmation' "$(val S3 "$out")" true
expect 'G4 add item after confirmation denied' "$(val G4 "$out")" false
expect 'G4 denied by confirmation lock (not duplicate check)' "$(reason $M ADD_ITEM)" MANIFEST_OPERATOR_OR_STATE_DENIED

echo "=== G1 service advances to DECIDED without a DECISION fact, then with one; service submits the confirmed manifest"
before="$(bootstrap_psql -Atqc "SELECT coalesce(max(event_id),0) FROM audit.access_events")"
out="$(session $SVC_P $SVC INTERNAL <<SQL
SELECT 'G1='||education.advance_application('$APP','DECIDED');
SELECT 'S6='||education.record_external_fact('$FACT_SVC','$APP','DECISION','Synthetic Institution','SYN-REF-SVC',clock_timestamp()-interval '1 hour');
SELECT 'S7='||education.advance_application('$APP','DECIDED');
SELECT 'S8='||docs.submit_manifest('$M');
SQL
)"; printf '%s\n' "$out"
expect 'G1 authorized actor without DECISION fact denied' "$(val G1 "$out")" false
expect 'G1 first ADVANCE audit row in this session' "$(bootstrap_psql -Atqc "SELECT decision||'/'||reason_code FROM audit.access_events WHERE event_id>$before AND resource_id='$APP' AND action='ADVANCE' ORDER BY event_id LIMIT 1")" DENY/STATE_OR_DECISION_FACT_DENIED
expect 'S6 service records DECISION fact' "$(val S6 "$out")" true
expect 'S7 same transition allowed once the fact exists' "$(val S7 "$out")" true
expect 'S8 service submits family-confirmed manifest' "$(val S8 "$out")" true

echo "=== G3 confirmer and submitter are different people (person check + table constraint)"
expect 'G3 manifest_distinct_actors constraint present' "$(bootstrap_psql -Atqc "SELECT count(*) FROM pg_constraint WHERE conname='manifest_distinct_actors'")" 1
expect 'G3 submitted manifest has confirmer <> submitter' "$(bootstrap_psql -Atqc "SELECT (confirmed_by IS NOT NULL AND submitted_by IS NOT NULL AND confirmed_by<>submitted_by) FROM docs.submission_manifests WHERE submission_id='$M'")" t
expect 'G3 no submitted manifest anywhere with confirmer = submitter' "$(bootstrap_psql -Atqc "SELECT count(*) FROM docs.submission_manifests WHERE status='SUBMITTED' AND confirmed_by=submitted_by")" 0

echo "=== R-20 observation: channel is not bound to principal kind at ticket issue"
out="$(session $G_P $G ADVISOR <<SQL
SELECT 'R20=redeemed';
SQL
)"; printf '%s\n' "$out"

[ "$fail" = 0 ] && echo "PASS Claude V1.4 D6 gap probes" || { echo "FAIL Claude V1.4 D6 gap probes"; exit 1; }
