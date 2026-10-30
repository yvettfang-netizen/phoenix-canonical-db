#!/usr/bin/env bash
# Enterprise V2.0 P1 permanent regression. Synthetic data and split LOGINs only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
CRM1=018f0000-0000-7000-8000-000000027001
CRM2=018f0000-0000-7000-8000-000000027002
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
CLIENT=018f0000-0000-7000-8000-000000026302
CAMPAIGN=018f0000-0000-7000-8000-000000027101
SOURCE=018f0000-0000-7000-8000-000000027102
LEAD1=018f0000-0000-7000-8000-000000027201
LEAD2=018f0000-0000-7000-8000-000000027202
LEAD_CROSS=018f0000-0000-7000-8000-000000027203
ATTR1=018f0000-0000-7000-8000-000000027211
ATTR2=018f0000-0000-7000-8000-000000027212
ATTR_CROSS=018f0000-0000-7000-8000-000000027213
LINK1=018f0000-0000-7000-8000-000000027301
LINK2=018f0000-0000-7000-8000-000000027302
LINK_BAD=018f0000-0000-7000-8000-000000027303
CANDIDATE=018f0000-0000-7000-8000-000000027321
MERGE_DECISION=018f0000-0000-7000-8000-000000027322
DEAL=018f0000-0000-7000-8000-000000027401
ITEM1=018f0000-0000-7000-8000-000000027411
ITEM2=018f0000-0000-7000-8000-000000027412
ITEM3=018f0000-0000-7000-8000-000000027413
HASH=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

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

test "$(bootstrap_psql -Atqc "SELECT auth.install_service_principal('$CRM1','canonical_crm_v2')")" = t
test "$(bootstrap_psql -Atqc "SELECT auth.install_service_principal('$CRM2','canonical_crm_v2')")" = t

cat >/tmp/f10-0027-source.sql <<SQL
SELECT 'CAMPAIGN='||crm.register_campaign('$CAMPAIGN','SYN_CAMPAIGN_027','Synthetic Cross Compass Campaign','ACTIVE',clock_timestamp()-interval '1 day',clock_timestamp()+interval '30 days');
SELECT 'SOURCE='||crm.register_lead_source('$SOURCE','phoenix_compass','WEBSITE','$CAMPAIGN',NULL);
SELECT 'LEAD1='||crm.create_lead('$LEAD1','$SOURCE',NULL,NULL,'$CRM1','CHILD_COMPASS','v1','018f0000-0000-7000-8000-000000027501','$ATTR1');
SELECT 'LEAD2='||crm.create_lead('$LEAD2','$SOURCE',NULL,NULL,'$CRM1','EDUCATION_COMPASS','v1','018f0000-0000-7000-8000-000000027502','$ATTR2');
SQL
out="$(run_session "$CRM1" NULL 018f0000-0000-7000-8000-000000027601 /tmp/f10-0027-source.sql)"
for expected in CAMPAIGN=true SOURCE=true LEAD1=true LEAD2=true; do expect_line "$expected" "$out"; done
test "$(bootstrap_psql -Atqc "SELECT count(*) FROM crm.leads WHERE lead_source_id='$SOURCE'")" = 2
echo 'PASS two unverified Leads from the same source remain distinct; no name/phone/OpenID auto-deduplication exists'

cat >/tmp/f10-0027-link1.sql <<SQL
SELECT 'LINK1='||crm.link_lead_identity('$LINK1','$LEAD1','CLIENT','$CLIENT','$HASH','018f0000-0000-7000-8000-000000027503');
SELECT 'SAME_REVIEWER='||crm.verify_lead_identity('$LINK1','018f0000-0000-7000-8000-000000027504');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000027602 /tmp/f10-0027-link1.sql)"
expect_line 'LINK1=true' "$out"; expect_line 'SAME_REVIEWER=false' "$out"
cat >/tmp/f10-0027-verify1.sql <<SQL
SELECT 'VERIFY1='||crm.verify_lead_identity('$LINK1','018f0000-0000-7000-8000-000000027505');
SQL
out="$(run_session "$CRM2" "$FAMILY_A" 018f0000-0000-7000-8000-000000027603 /tmp/f10-0027-verify1.sql)"; expect_line 'VERIFY1=true' "$out"

cat >/tmp/f10-0027-link2.sql <<SQL
SELECT 'LINK2='||crm.link_lead_identity('$LINK2','$LEAD2','CLIENT','$CLIENT','$HASH','018f0000-0000-7000-8000-000000027506');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000027604 /tmp/f10-0027-link2.sql)"; expect_line 'LINK2=true' "$out"
cat >/tmp/f10-0027-verify2.sql <<SQL
SELECT 'VERIFY2='||crm.verify_lead_identity('$LINK2','018f0000-0000-7000-8000-000000027507');
SQL
out="$(run_session "$CRM2" "$FAMILY_A" 018f0000-0000-7000-8000-000000027605 /tmp/f10-0027-verify2.sql)"; expect_line 'VERIFY2=true' "$out"
test "$(bootstrap_psql -Atqc "SELECT count(*) FROM crm.lead_identity_links WHERE client_id='$CLIENT' AND status='VERIFIED'")" = 2
echo 'PASS two Leads may resolve to one Client only through distinct-principal verified links'

cat >/tmp/f10-0027-candidate.sql <<SQL
SELECT 'CANDIDATE='||crm.propose_lead_duplicate('$CANDIDATE','$LEAD1','$LEAD2','$HASH','018f0000-0000-7000-8000-000000027508');
SELECT 'SAME_REVIEWER='||crm.review_lead_duplicate('$CANDIDATE','CONFIRMED','018f0000-0000-7000-8000-000000027513');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000027606 /tmp/f10-0027-candidate.sql)"
expect_line 'CANDIDATE=true' "$out"; expect_line 'SAME_REVIEWER=false' "$out"
cat >/tmp/f10-0027-review.sql <<SQL
SELECT 'REVIEW='||crm.review_lead_duplicate('$CANDIDATE','CONFIRMED','018f0000-0000-7000-8000-000000027514');
SQL
out="$(run_session "$CRM2" "$FAMILY_A" 018f0000-0000-7000-8000-000000027609 /tmp/f10-0027-review.sql)"; expect_line 'REVIEW=true' "$out"

cat >/tmp/f10-0027-merge-revoke.sql <<SQL
SELECT 'MERGE='||crm.merge_lead('$MERGE_DECISION','$LEAD2','$LEAD1','$CANDIDATE','018f0000-0000-7000-8000-000000027515');
SELECT 'REVOKE_BAD_LINK='||crm.revoke_lead_identity('$LINK2','018f0000-0000-7000-8000-000000027509');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000027610 /tmp/f10-0027-merge-revoke.sql)"
expect_line 'MERGE=true' "$out"; expect_line 'REVOKE_BAD_LINK=true' "$out"
state="$(bootstrap_psql -Atqc "SELECT (SELECT lead_status FROM crm.leads WHERE lead_id='$LEAD2')||'|'||(SELECT status FROM crm.lead_identity_links WHERE lead_identity_link_id='$LINK2')")"
test "$state" = 'MERGED|REVOKED' || { echo "FAIL merge/revoke=$state" >&2; exit 1; }
echo 'PASS audited Lead merge preserves source Lead and mistaken identity association can be revoked'

cat >/tmp/f10-0027-deal.sql <<SQL
SELECT 'DEAL='||crm.create_deal('$DEAL','$CLIENT','$FAMILY_A','$LEAD1','Synthetic Multi Compass Deal','MULTI_DOMAIN',12345.67,'CNY',clock_timestamp()+interval '20 days','$CRM1','018f0000-0000-7000-8000-000000027510');
SELECT 'CHILD='||crm.add_deal_item('$ITEM1','$DEAL','CHILD_027','Synthetic Child Compass','EDUCATION','CHILD_COMPASS',1,1000.00,'CNY');
SELECT 'EDU='||crm.add_deal_item('$ITEM2','$DEAL','EDU_027','Synthetic Education Compass','EDUCATION','EDUCATION_COMPASS',1,2000.00,'CNY');
SELECT 'FAMILY='||crm.add_deal_item('$ITEM3','$DEAL','FAMILY_027','Synthetic Family Compass','WEALTH','FAMILY_COMPASS',1,3000.00,'CNY');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000027607 /tmp/f10-0027-deal.sql)"
for expected in DEAL=true CHILD=true EDU=true FAMILY=true; do expect_line "$expected" "$out"; done
compasses="$(bootstrap_psql -Atqc "SELECT string_agg(compass_kind,',' ORDER BY compass_kind) FROM crm.deal_items WHERE deal_id='$DEAL'")"
test "$compasses" = 'CHILD_COMPASS,EDUCATION_COMPASS,FAMILY_COMPASS' || { echo "FAIL compasses=$compasses" >&2; exit 1; }
numeric_type="$(bootstrap_psql -Atqc "SELECT data_type||'|'||numeric_precision||'|'||numeric_scale FROM information_schema.columns WHERE table_schema='crm' AND table_name='deals' AND column_name='estimated_amount'")"
test "$numeric_type" = 'numeric|18|2' || { echo "FAIL deal amount type=$numeric_type" >&2; exit 1; }
echo 'PASS Deal uses NUMERIC money and carries three explicit Compass attributions without new master data'

cat >/tmp/f10-0027-cross.sql <<SQL
SELECT 'CROSS_FAMILY='||crm.create_lead('$LEAD_CROSS','$SOURCE',NULL,'$FAMILY_A','$CRM1','FAMILY_COMPASS','v1','018f0000-0000-7000-8000-000000027511','$ATTR_CROSS');
SELECT 'BAD_TARGET='||crm.link_lead_identity('$LINK_BAD','$LEAD1','CLIENT','018f0000-0000-7000-8000-000000027999','$HASH','018f0000-0000-7000-8000-000000027512');
SQL
out="$(run_session "$CRM1" "$FAMILY_B" 018f0000-0000-7000-8000-000000027608 /tmp/f10-0027-cross.sql)"
expect_line 'CROSS_FAMILY=false' "$out"; expect_line 'BAD_TARGET=false' "$out"

if app_psql -Atqc "INSERT INTO crm.leads(lead_id,lead_source_id,lead_status,qualification_status,created_by_principal_id,updated_by_principal_id) VALUES('$LEAD_CROSS','$SOURCE','NEW','UNVERIFIED','$CRM1','$CRM1')" >/tmp/f10-0027-acl.out 2>&1; then
  echo 'FAIL app direct Lead INSERT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0027-acl.out
event_update="$(bootstrap_psql -Atqc "UPDATE crm.lead_events SET reason_code='FORGED' WHERE lead_id='$LEAD1'" 2>&1 || true)"
grep -q 'CRM_LEAD_EVENT_IMMUTABLE' <<<"$event_update" || { echo "FAIL event immutability=$event_update" >&2; exit 1; }
acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','crm.leads','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','crm.deals','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_function_privilege('public','crm.create_lead(uuid,uuid,uuid,uuid,uuid,text,text,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_lead(uuid,uuid,uuid,uuid,uuid,text,text,uuid,uuid)','EXECUTE')::text")"
test "$acl" = 'false|false|false|false|true' || { echo "FAIL P1 ACL=$acl" >&2; exit 1; }
audit="$(bootstrap_psql -Atqc "SELECT count(*) FILTER (WHERE decision='ALLOW')||'|'||count(*) FILTER (WHERE decision='DENY') FROM audit.access_events WHERE resource_kind LIKE 'CRM_%'")"
IFS='|' read -r allow_count deny_count <<<"$audit"; test "$allow_count" -gt 0 && test "$deny_count" -gt 0
echo 'PASS 0027 CRM tenant isolation, immutable events, exact ACL and allow/deny audit regression'

