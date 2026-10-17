#!/usr/bin/env bash
# Permanent G1-G5 and service-principal regressions, synthetic data only.
set -euo pipefail
app_psql() { PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
backup_psql() { PGPASSFILE=/tmp/f10-backup.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001
G_P=018f0000-0000-7000-8000-000000002002; G=018f0000-0000-7000-8000-000000001002
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004
SVC_P=018f0000-0000-7000-8000-000000002001
STU=018f0000-0000-7000-8000-000000001003
APP=018f0000-0000-7000-8000-00000000a001
VER=018f0000-0000-7000-8000-000000006101
M=018f0000-0000-7000-8000-00000000a002
FACT_FAM=018f0000-0000-7000-8000-00000000a003
FACT_SVC=018f0000-0000-7000-8000-00000000a004
session() { local actor="'$2'::uuid" t; [ "$2" = NULL ] && actor=NULL;
  t="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$1',$actor,'$FA','$3',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$1"; cat; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
reason() { backup_psql -Atqc "SELECT reason_code FROM audit.access_events WHERE resource_id='$1' AND action='$2' ORDER BY event_id DESC LIMIT 1"; }
expect() { if [ "$2" != "$3" ]; then echo "FAIL $1 got=$2 expected=$3"; exit 1; fi; echo "PASS $1=$2"; }
value() { sed -n "s/^$1=//p" <<<"$2" | head -1; }

out="$(session "$G_P" "$G" FAMILY <<SQL
SELECT 'S0='||education.create_application('$APP','$FA','$STU','Synthetic Institution','Synthetic Programme','2029');
SELECT 'S1='||docs.create_submission_manifest('$M','$FA','$STU','EDUCATION_APPLICATION','$APP');
SELECT 'S2='||docs.add_submission_item('$M',1,'$VER');
SELECT 'G2='||education.record_external_fact('$FACT_FAM','$APP','DECISION','Synthetic Institution','SYN-REF-FAM',clock_timestamp()-interval '1 hour');
SELECT 'S4='||education.advance_application('$APP','READY');
SELECT 'S5='||education.advance_application('$APP','SUBMITTED');
SQL
)"
for field in S0 S1 S2 S4 S5; do expect "setup-$field" "$(value "$field" "$out")" true; done
expect G2 "$(value G2 "$out")" false
expect G2_reason "$(reason "$FACT_FAM" RECORD)" OFFICIAL_FACT_AUTHORITY_OR_INPUT_DENIED

out="$(session "$ADV_P" "$ADV" ADVISOR <<SQL
SELECT 'G5='||docs.confirm_manifest('$M');
SQL
)"
expect G5 "$(value G5 "$out")" false
expect G5_reason "$(reason "$M" CONFIRM)" FAMILY_AUTHORITY_OR_STATE_DENIED

out="$(session "$G_P" "$G" FAMILY <<SQL
SELECT 'S3='||docs.confirm_manifest('$M');
SELECT 'G4='||docs.add_submission_item('$M',2,'$VER');
SQL
)"
expect S3 "$(value S3 "$out")" true
expect G4 "$(value G4 "$out")" false
expect G4_reason "$(reason "$M" ADD_ITEM)" MANIFEST_OPERATOR_OR_STATE_DENIED

out="$(session "$SVC_P" NULL INTERNAL <<SQL
SELECT 'G1='||education.advance_application('$APP','DECIDED');
SELECT 'S6='||education.record_external_fact('$FACT_SVC','$APP','DECISION','Synthetic Institution','SYN-REF-SVC',clock_timestamp()-interval '1 hour');
SELECT 'S7='||education.advance_application('$APP','DECIDED');
SELECT 'S8='||docs.submit_manifest('$M');
SQL
)"
expect G1 "$(value G1 "$out")" false
expect S6 "$(value S6 "$out")" true
expect S7 "$(value S7 "$out")" true
expect S8 "$(value S8 "$out")" true
expect G3_attribution "$(backup_psql -Atqc "SELECT confirmed_by IS NOT NULL AND submitted_by IS NULL AND submitted_by_principal_id='$SVC_P' FROM docs.submission_manifests WHERE submission_id='$M'")" t
expect G3_no_same_person "$(backup_psql -Atqc "SELECT count(*) FROM docs.submission_manifests WHERE status='SUBMITTED' AND confirmed_by=submitted_by")" 0
expect service_has_no_person "$(backup_psql -Atqc "SELECT person_id IS NULL FROM auth.principals WHERE principal_id='$SVC_P'")" t
echo 'PASS permanent G1-G5 with split LOGIN and one-use tickets'
