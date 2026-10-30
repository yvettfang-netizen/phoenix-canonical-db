#!/usr/bin/env bash
# M3 permanent regression. Synthetic rows and split LOGIN accounts only.
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
LEAD=018f0000-0000-7000-8000-000000027201
CONSULT=018f0000-0000-7000-8000-000000033101
DEAL=018f0000-0000-7000-8000-000000033201
ASSIGN1=018f0000-0000-7000-8000-000000033211
ASSIGN2=018f0000-0000-7000-8000-000000033212
ITEM1=018f0000-0000-7000-8000-000000033221
ITEM2=018f0000-0000-7000-8000-000000033222
CANDIDATE=018f0000-0000-7000-8000-000000033231
FOLLOW=018f0000-0000-7000-8000-000000033241

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U "$APP"    -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local principal="$1" family="$2" nonce="$3" file="$4" ticket
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',NULL,'$family'::uuid,'INTERNAL',clock_timestamp()+interval '45 seconds','$nonce','$principal')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"; cat "$file"; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

cat >/tmp/f10-0033-consultation.sql <<SQL
SELECT 'CREATE='||crm.create_consultation('$CONSULT','$LEAD','$CLIENT','$FAMILY_A',NULL,'HEALTH','NEEDS_ANALYSIS','HEALTH_COMPASS','$CRM2',clock_timestamp()+interval '1 day','018f0000-0000-7000-8000-000000033301');
SELECT 'START='||crm.transition_consultation('$CONSULT','IN_PROGRESS',NULL,NULL,'018f0000-0000-7000-8000-000000033302');
SELECT 'COMPLETE='||crm.transition_consultation('$CONSULT','COMPLETED','NEEDS_CAPTURED','PROPOSAL_REVIEW','018f0000-0000-7000-8000-000000033303');
SELECT 'REOPEN='||crm.transition_consultation('$CONSULT','IN_PROGRESS',NULL,NULL,'018f0000-0000-7000-8000-000000033304');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000033401 /tmp/f10-0033-consultation.sql)"
for expected in CREATE=true START=true COMPLETE=true REOPEN=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0033-deal.sql <<SQL
SELECT 'DEAL='||crm.create_managed_deal('$DEAL','$ASSIGN1','$CLIENT','$FAMILY_A','$LEAD','$CONSULT','Synthetic Managed Deal','MULTI_DOMAIN',25000.00,'CNY',clock_timestamp()+interval '30 days','$CRM2',NULL,'018f0000-0000-7000-8000-000000033311');
SELECT 'EDU='||crm.add_managed_deal_item('$ITEM1','$DEAL','EDU_033','Synthetic Education Scope','EDUCATION','EDUCATION_COMPASS',1,12000.00,'CNY','018f0000-0000-7000-8000-000000033312');
SELECT 'HEALTH='||crm.add_managed_deal_item('$ITEM2','$DEAL','HEALTH_033','Synthetic Health Scope','HEALTH','HEALTH_COMPASS',1,13000.00,'CNY','018f0000-0000-7000-8000-000000033313');
SELECT 'CANDIDATE='||crm.add_deal_project_candidate('$CANDIDATE','$DEAL','PROJECT_033','EDUCATION','EDUCATION_COMPASS','018f0000-0000-7000-8000-000000033314');
SELECT 'AMOUNT='||crm.revise_deal_amount('$DEAL',26000.00,'CNY','SCOPE_REPRICED','018f0000-0000-7000-8000-000000033315');
SELECT 'FOLLOW='||crm.schedule_follow_up('$FOLLOW','DEAL',NULL,'$DEAL',NULL,'Synthetic proposal follow up','$CRM1',clock_timestamp()+interval '2 days');
SELECT 'FOLLOW_DONE='||crm.transition_follow_up('$FOLLOW','COMPLETED');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000033402 /tmp/f10-0033-deal.sql)"
for expected in DEAL=true EDU=true HEALTH=true CANDIDATE=true AMOUNT=true FOLLOW=true FOLLOW_DONE=true; do expect_line "$expected" "$out"; done

# Disable the old sales owner, then prove the controlled handoff still works.
test "$(bootstrap_psql -Atqc "SELECT auth.disable_service_principal('$CRM2')")" = t
cat >/tmp/f10-0033-handoff.sql <<SQL
SELECT 'TRANSFER='||crm.transfer_deal_owner('$DEAL','$ASSIGN2','$CRM1','DISABLED_OWNER_HANDOFF','018f0000-0000-7000-8000-000000033321');
SELECT 'QUALIFIED='||crm.transition_deal('$DEAL','QUALIFIED','QUALIFICATION_COMPLETE','018f0000-0000-7000-8000-000000033322');
SELECT 'PROPOSAL='||crm.transition_deal('$DEAL','PROPOSAL','PROPOSAL_ISSUED','018f0000-0000-7000-8000-000000033323');
SELECT 'NEGOTIATION='||crm.transition_deal('$DEAL','NEGOTIATION','NEGOTIATION_OPENED','018f0000-0000-7000-8000-000000033324');
SELECT 'WON='||crm.transition_deal('$DEAL','WON','CLIENT_ACCEPTED','018f0000-0000-7000-8000-000000033325');
SELECT 'TERMINAL_AMOUNT='||crm.revise_deal_amount('$DEAL',1.00,'CNY','FORGED_REPRICE','018f0000-0000-7000-8000-000000033326');
SQL
out="$(run_session "$CRM1" "$FAMILY_A" 018f0000-0000-7000-8000-000000033403 /tmp/f10-0033-handoff.sql)"
for expected in TRANSFER=true QUALIFIED=true PROPOSAL=true NEGOTIATION=true WON=true TERMINAL_AMOUNT=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0033-cross.sql <<SQL
SELECT 'CROSS='||crm.create_consultation('018f0000-0000-7000-8000-000000033199','$LEAD','$CLIENT','$FAMILY_A',NULL,'EDUCATION','DISCOVERY','EDUCATION_COMPASS','$CRM1',clock_timestamp()+interval '1 day','018f0000-0000-7000-8000-000000033399');
SQL
out="$(run_session "$CRM1" "$FAMILY_B" 018f0000-0000-7000-8000-000000033404 /tmp/f10-0033-cross.sql)"; expect_line 'CROSS=false' "$out"

catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT status||':'||result_code||':'||next_action_code FROM crm.consultations WHERE consultation_id='$CONSULT')||'|'||
  (SELECT deal_status||':'||estimated_amount::text||':'||owner_principal_id::text||':'||won_lost_reason_code FROM crm.deals WHERE deal_id='$DEAL')||'|'||
  (SELECT count(*) FROM crm.sales_assignments WHERE deal_id='$DEAL')||'|'||
  (SELECT count(*) FROM crm.deal_events WHERE deal_id='$DEAL')||'|'||
  (SELECT status FROM crm.follow_ups WHERE follow_up_id='$FOLLOW')")"
test "$catalog" = "COMPLETED:NEEDS_CAPTURED:PROPOSAL_REVIEW|WON:26000.00:$CRM1:CLIENT_ACCEPTED|2|10|COMPLETED" || { echo "FAIL M3 catalog=$catalog" >&2; exit 1; }

questionnaire_columns="$(bootstrap_psql -Atqc "SELECT count(*) FROM information_schema.columns WHERE table_schema='crm' AND table_name='consultations' AND column_name ~ '(questionnaire|diagnosis|medical|symptom|answer|response)' ")"
test "$questionnaire_columns" = 0 || { echo "FAIL Health raw questionnaire column count=$questionnaire_columns" >&2; exit 1; }
event_update="$(bootstrap_psql -Atqc "UPDATE crm.deal_events SET reason_code='FORGED' WHERE deal_id='$DEAL'" 2>&1 || true)"
grep -q 'CRM_M3_HISTORY_IMMUTABLE' <<<"$event_update" || { echo "FAIL deal event immutability=$event_update" >&2; exit 1; }
if app_psql -Atqc "SELECT count(*) FROM crm.deal_events" >/tmp/f10-0033-acl.out 2>&1; then
  echo 'FAIL app direct Deal Event SELECT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0033-acl.out
acl="$(bootstrap_psql -Atqc "SELECT
  has_function_privilege('public','crm.create_managed_deal(uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_deal(uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.add_deal_item(uuid,uuid,text,text,text,text,numeric,numeric,text)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_managed_deal(uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid,uuid)','EXECUTE')::text")"
test "$acl" = 'false|false|false|true' || { echo "FAIL M3 ACL=$acl" >&2; exit 1; }
echo 'PASS M3 Consultation/Deal lifecycle, numeric history, project candidates, disabled-owner handoff, terminal lock, Health payload boundary and exact ACL'
