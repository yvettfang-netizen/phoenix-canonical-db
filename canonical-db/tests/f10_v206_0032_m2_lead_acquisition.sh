#!/usr/bin/env bash
# M2 permanent regression. Synthetic data, split LOGIN accounts and manual identity/dedup only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
CRM1=018f0000-0000-7000-8000-000000027001
CRM2=018f0000-0000-7000-8000-000000027002
FAMILY_A=018f0000-0000-7000-8000-000000000001
SOURCE=018f0000-0000-7000-8000-000000027102
LEAD1=018f0000-0000-7000-8000-000000027201
LEAD2=018f0000-0000-7000-8000-000000027202
CANDIDATE=018f0000-0000-7000-8000-000000027321
MERGE1=018f0000-0000-7000-8000-000000027322
PARTNER=018f0000-0000-7000-8000-000000031303
LEAD3=018f0000-0000-7000-8000-000000032101
LEAD4=018f0000-0000-7000-8000-000000032102
ATTR3=018f0000-0000-7000-8000-000000032111
ATTR4=018f0000-0000-7000-8000-000000032112
CONVERSION=018f0000-0000-7000-8000-000000032121
REFERRAL=018f0000-0000-7000-8000-000000032201
MERGE2=018f0000-0000-7000-8000-000000032301

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

cat >/tmp/f10-0032-new-leads.sql <<SQL
SELECT 'FAMILY_COMPASS='||crm.create_lead('$LEAD3','$SOURCE',NULL,NULL,'$CRM1','FAMILY_COMPASS','v2','018f0000-0000-7000-8000-000000032401','$ATTR3');
SELECT 'HEALTH_COMPASS='||crm.create_lead('$LEAD4','$SOURCE',NULL,NULL,'$CRM1','HEALTH_COMPASS','v2','018f0000-0000-7000-8000-000000032402','$ATTR4');
SELECT 'CONTACTED='||crm.transition_lead('$LEAD3','CONTACTED','018f0000-0000-7000-8000-000000032403');
SELECT 'QUALIFIED='||crm.transition_lead('$LEAD3','QUALIFIED','018f0000-0000-7000-8000-000000032404');
SELECT 'LOST='||crm.transition_lead('$LEAD3','LOST','018f0000-0000-7000-8000-000000032405');
SELECT 'TERMINAL_REOPEN='||crm.transition_lead('$LEAD3','QUALIFIED','018f0000-0000-7000-8000-000000032406');
SELECT 'DISQUALIFIED='||crm.transition_lead('$LEAD4','DISQUALIFIED','018f0000-0000-7000-8000-000000032407');
SQL
out="$(run_session "$CRM1" NULL 018f0000-0000-7000-8000-000000032501 /tmp/f10-0032-new-leads.sql)"
for expected in FAMILY_COMPASS=true HEALTH_COMPASS=true CONTACTED=true QUALIFIED=true LOST=true TERMINAL_REOPEN=false DISQUALIFIED=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0032-conversion-referral.sql <<SQL
SELECT 'CONVERSION='||crm.record_conversion_attribution('$CONVERSION','$LEAD1','$SOURCE','$PARTNER','EDUCATION_COMPASS','v2','018f0000-0000-7000-8000-000000032411');
SELECT 'CONVERSION_DUP='||crm.record_conversion_attribution('018f0000-0000-7000-8000-000000032122','$LEAD1','$SOURCE','$PARTNER','EDUCATION_COMPASS','v2','018f0000-0000-7000-8000-000000032412');
SELECT 'REFERRAL='||crm.record_referral('$REFERRAL','$LEAD1','$PARTNER','018f0000-0000-7000-8000-000000032421');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000032502 /tmp/f10-0032-conversion-referral.sql)"
for expected in CONVERSION=true CONVERSION_DUP=false REFERRAL=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0032-referral-confirm.sql <<SQL
SELECT 'CONFIRM='||crm.transition_referral('$REFERRAL','CONFIRMED','018f0000-0000-7000-8000-000000032422');
SQL
out="$(run_session "$CRM2" "$FAMILY_A" 018f0000-0000-7000-8000-000000032503 /tmp/f10-0032-referral-confirm.sql)"; expect_line 'CONFIRM=true' "$out"
cat >/tmp/f10-0032-referral-revoke.sql <<SQL
SELECT 'REVOKE='||crm.transition_referral('$REFERRAL','REVOKED','018f0000-0000-7000-8000-000000032423');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000032504 /tmp/f10-0032-referral-revoke.sql)"; expect_line 'REVOKE=true' "$out"

cat >/tmp/f10-0032-reverse-remerge.sql <<SQL
SELECT 'REVERSE='||crm.reverse_lead_merge('$MERGE1','018f0000-0000-7000-8000-000000032431');
SELECT 'REMERGE='||crm.merge_lead('$MERGE2','$LEAD2','$LEAD1','$CANDIDATE','018f0000-0000-7000-8000-000000032432');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000032505 /tmp/f10-0032-reverse-remerge.sql)"
expect_line 'REVERSE=true' "$out"; expect_line 'REMERGE=true' "$out"

catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(DISTINCT compass_kind) FROM crm.lead_attributions WHERE attribution_kind='FIRST_TOUCH')||'|'||
  (SELECT count(*) FROM crm.lead_attributions WHERE lead_id='$LEAD1' AND attribution_kind='CONVERSION_TOUCH')||'|'||
  (SELECT count(*) FROM crm.referral_events WHERE referral_id='$REFERRAL')||'|'||
  (SELECT count(*) FROM crm.lead_merge_decisions WHERE source_lead_id='$LEAD2')||'|'||
  (SELECT count(*) FROM crm.leads WHERE lead_id IN ('$LEAD3','$LEAD4') AND contact_person_id IS NULL AND family_id IS NULL)")"
test "$catalog" = '4|1|3|2|2' || { echo "FAIL M2 catalog=$catalog" >&2; exit 1; }
state="$(bootstrap_psql -Atqc "SELECT
  (SELECT lead_status FROM crm.leads WHERE lead_id='$LEAD3')||'|'||
  (SELECT lead_status FROM crm.leads WHERE lead_id='$LEAD4')||'|'||
  (SELECT status FROM crm.referrals WHERE referral_id='$REFERRAL')||'|'||
  (SELECT lead_status FROM crm.leads WHERE lead_id='$LEAD2')")"
test "$state" = 'LOST|DISQUALIFIED|REVOKED|MERGED' || { echo "FAIL M2 state=$state" >&2; exit 1; }

immutable="$(bootstrap_psql -Atqc "UPDATE crm.lead_attributions SET attribution_model_version='forged' WHERE lead_attribution_id='$ATTR3'" 2>&1 || true)"
grep -q 'CRM_ACQUISITION_HISTORY_IMMUTABLE' <<<"$immutable" || { echo "FAIL first touch mutation=$immutable" >&2; exit 1; }
if app_psql -Atqc "SELECT count(*) FROM crm.lead_attributions" >/tmp/f10-0032-acl.out 2>&1; then
  echo 'FAIL app direct Lead Attribution SELECT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0032-acl.out
acl="$(bootstrap_psql -Atqc "SELECT
  has_function_privilege('public','crm.transition_lead(uuid,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.transition_lead(uuid,text,uuid)','EXECUTE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','crm.referral_events','SELECT')::text")"
test "$acl" = 'false|false|true|false' || { echo "FAIL M2 ACL=$acl" >&2; exit 1; }
echo 'PASS M2 four-Compass First Touch, immutable conversion attribution, manual dedup/reversal, referral events, lifecycle and exact ACL'
