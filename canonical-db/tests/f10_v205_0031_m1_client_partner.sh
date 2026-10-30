#!/usr/bin/env bash
# M1 permanent regression. Synthetic data and split LOGIN accounts only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
MGMT=018f0000-0000-7000-8000-000000002001
CRM=018f0000-0000-7000-8000-000000027001
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
CLIENT=018f0000-0000-7000-8000-000000026302
PERSON=018f0000-0000-7000-8000-000000026101
ORG_A=018f0000-0000-7000-8000-000000026201
ORG_B=018f0000-0000-7000-8000-000000030201
SOURCE=018f0000-0000-7000-8000-000000027102
CP1=018f0000-0000-7000-8000-000000031101
CP_DUP=018f0000-0000-7000-8000-000000031102
CP_REJOIN=018f0000-0000-7000-8000-000000031103
CP_ORG=018f0000-0000-7000-8000-000000031104
PR1=018f0000-0000-7000-8000-000000031301
PR_DUP=018f0000-0000-7000-8000-000000031302
PR_REJOIN=018f0000-0000-7000-8000-000000031303
PR_ORG=018f0000-0000-7000-8000-000000031304

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

cat >/tmp/f10-0031-student.sql <<SQL
SELECT 'STUDENT='||core.create_student_profile('$PERSON');
SQL
out="$(run_session "$MGMT" "$FAMILY_A" 018f0000-0000-7000-8000-000000031501 /tmp/f10-0031-student.sql)"
expect_line 'STUDENT=true' "$out"

cat >/tmp/f10-0031-client-parties.sql <<SQL
SELECT 'PERSON_PARTY='||crm.add_client_party('$CP1','$CLIENT','PERSON','$PERSON','CLIENT_CONTACT',NULL,'018f0000-0000-7000-8000-000000031201');
SELECT 'PERSON_DUP='||crm.add_client_party('$CP_DUP','$CLIENT','PERSON','$PERSON','CLIENT_CONTACT',NULL,'018f0000-0000-7000-8000-000000031202');
SELECT 'PERSON_END='||crm.end_client_party('$CP1','018f0000-0000-7000-8000-000000031203');
SELECT 'PERSON_REJOIN='||crm.add_client_party('$CP_REJOIN','$CLIENT','PERSON','$PERSON','CLIENT_CONTACT',NULL,'018f0000-0000-7000-8000-000000031204');
SELECT 'ORG_PAYER='||crm.add_client_party('$CP_ORG','$CLIENT','ORGANIZATION','$ORG_B','PAYER',NULL,'018f0000-0000-7000-8000-000000031205');
SQL
out="$(run_session "$CRM" "$FAMILY_A" 018f0000-0000-7000-8000-000000031502 /tmp/f10-0031-client-parties.sql)"
for expected in PERSON_PARTY=true PERSON_DUP=false PERSON_END=true PERSON_REJOIN=true ORG_PAYER=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0031-cross.sql <<SQL
SELECT 'CROSS_FAMILY='||crm.add_client_party('$CP_DUP','$CLIENT','PERSON','$PERSON','AUTHORIZED_REPRESENTATIVE',NULL,'018f0000-0000-7000-8000-000000031206');
SQL
out="$(run_session "$CRM" "$FAMILY_B" 018f0000-0000-7000-8000-000000031503 /tmp/f10-0031-cross.sql)"
expect_line 'CROSS_FAMILY=false' "$out"

cat >/tmp/f10-0031-partners.sql <<SQL
SELECT 'PERSON_PARTNER='||crm.create_partner_relationship('$PR1','PERSON','$PERSON','REFERRAL_PARTNER','$SOURCE',NULL,'018f0000-0000-7000-8000-000000031401');
SELECT 'PERSON_DUP='||crm.create_partner_relationship('$PR_DUP','PERSON','$PERSON','REFERRAL_PARTNER','$SOURCE',NULL,'018f0000-0000-7000-8000-000000031402');
SELECT 'PERSON_END='||crm.end_partner_relationship('$PR1','018f0000-0000-7000-8000-000000031403');
SELECT 'PERSON_REJOIN='||crm.create_partner_relationship('$PR_REJOIN','PERSON','$PERSON','REFERRAL_PARTNER','$SOURCE',NULL,'018f0000-0000-7000-8000-000000031404');
SELECT 'ORG_PARTNER='||crm.create_partner_relationship('$PR_ORG','ORGANIZATION','$ORG_A','INSTITUTIONAL_PARTNER',NULL,NULL,'018f0000-0000-7000-8000-000000031405');
SQL
out="$(run_session "$CRM" NULL 018f0000-0000-7000-8000-000000031504 /tmp/f10-0031-partners.sql)"
for expected in PERSON_PARTNER=true PERSON_DUP=false PERSON_END=true PERSON_REJOIN=true ORG_PARTNER=true; do expect_line "$expected" "$out"; done

catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(*) FROM crm.client_parties WHERE client_id='$CLIENT')||'|'||
  (SELECT count(*) FROM crm.partner_relationships)||'|'||
  (SELECT count(*) FROM crm.client_relationship_events WHERE client_id='$CLIENT')||'|'||
  (SELECT count(*) FROM crm.partner_relationship_events)||'|'||
  (SELECT count(*) FROM core.student_profiles WHERE person_id='$PERSON')")"
test "$catalog" = '3|3|5|4|1' || { echo "FAIL M1 catalog=$catalog" >&2; exit 1; }

if app_psql -Atqc "DELETE FROM crm.client_parties WHERE client_party_id='$CP_REJOIN'" >/tmp/f10-0031-acl.out 2>&1; then
  echo 'FAIL app direct Client Party DELETE accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0031-acl.out

acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','crm.client_parties','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','crm.partner_relationships','SELECT')::text||'|'||
  has_table_privilege('phoenix_canonical_context_binder','crm.client_relationship_events','SELECT')::text||'|'||
  has_function_privilege('public','crm.add_client_party(uuid,uuid,text,uuid,text,timestamptz,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_client(uuid,uuid,text)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.add_client_party(uuid,uuid,text,uuid,text,timestamptz,uuid)','EXECUTE')::text")"
test "$acl" = 'false|false|false|false|false|true' || { echo "FAIL M1 ACL=$acl" >&2; exit 1; }

immutable="$(bootstrap_psql -Atqc "UPDATE crm.partner_relationship_events SET reason_code='FORBIDDEN' WHERE partner_relationship_event_id='018f0000-0000-7000-8000-000000031401'" 2>&1 || true)"
grep -q 'CRM_RELATIONSHIP_HISTORY_IMMUTABLE' <<<"$immutable" || { echo "FAIL M1 event mutation=$immutable" >&2; exit 1; }
echo 'PASS M1 unified Client parties, Person/Organization partners, lifecycle history, referral ownership, exact ACL and immutable events'
