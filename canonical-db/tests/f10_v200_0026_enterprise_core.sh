#!/usr/bin/env bash
# Enterprise Database V2.0 P0 permanent regression. Synthetic data and split
# LOGIN accounts only; every service context uses a one-use binder ticket.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
MGMT=018f0000-0000-7000-8000-000000002001
ENTERPRISE=018f0000-0000-7000-8000-000000002026
FAMILY_A=018f0000-0000-7000-8000-000000000001
FAMILY_B=018f0000-0000-7000-8000-000000000002
PERSON=018f0000-0000-7000-8000-000000026101
MEMBER_A=018f0000-0000-7000-8000-000000026102
MEMBER_B1=018f0000-0000-7000-8000-000000026103
MEMBER_B2=018f0000-0000-7000-8000-000000026104
MEMBER_B3=018f0000-0000-7000-8000-000000026105
ORG=018f0000-0000-7000-8000-000000026201
ORG_DUP=018f0000-0000-7000-8000-000000026202
ORG_INACTIVE_EVENT=018f0000-0000-7000-8000-000000026203
ORG_ACTIVE_EVENT=018f0000-0000-7000-8000-000000026204
CLIENT_A1=018f0000-0000-7000-8000-000000026301
CLIENT_A2=018f0000-0000-7000-8000-000000026302
CLIENT_DUP=018f0000-0000-7000-8000-000000026303
DIGEST=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U "$APP"    -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local principal="$1" family="$2" nonce="$3" file="$4" ticket family_sql
  family_sql=NULL; [ "$family" = NULL ] || family_sql="'$family'::uuid"
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',NULL,$family_sql,'INTERNAL',clock_timestamp()+interval '45 seconds','$nonce','$principal')")"
  {
    printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

test "$(bootstrap_psql -Atqc "SELECT auth.install_service_principal('$ENTERPRISE','canonical_enterprise_v2_core')")" = t

cat >/tmp/f10-0026-org.sql <<SQL
SELECT 'ORG_CREATE='||core.register_organization('$ORG','Synthetic Phoenix School Ltd','Synthetic Phoenix School','SCHOOL','CN','$DIGEST');
SELECT 'ORG_DUPLICATE='||core.register_organization('$ORG_DUP','Synthetic Phoenix School Ltd','Duplicate Business Role','SERVICE_PROVIDER','CN','$DIGEST');
SELECT 'ORG_INACTIVE='||core.transition_organization('$ORG','INACTIVE','$ORG_INACTIVE_EVENT');
SELECT 'ORG_ACTIVE='||core.transition_organization('$ORG','ACTIVE','$ORG_ACTIVE_EVENT');
SQL
out="$(run_session "$ENTERPRISE" NULL 018f0000-0000-7000-8000-000000026401 /tmp/f10-0026-org.sql)"
for expected in ORG_CREATE=true ORG_DUPLICATE=false ORG_INACTIVE=true ORG_ACTIVE=true; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0026-org-wrong-service.sql <<SQL
SELECT 'WRONG_SERVICE='||core.register_organization('$ORG_DUP','Wrong Service Org','Wrong Service Org','ENTERPRISE','CN',NULL);
SQL
out="$(run_session "$MGMT" NULL 018f0000-0000-7000-8000-000000026402 /tmp/f10-0026-org-wrong-service.sql)"
expect_line 'WRONG_SERVICE=false' "$out"
echo 'PASS canonical Organization uses controlled vocabulary, digest-only registration reference and exact SERVICE scope'

cat >/tmp/f10-0026-person-family-a.sql <<SQL
SELECT 'PERSON_A='||core.create_person('$PERSON','Synthetic Multi Family Person','$FAMILY_A','$MEMBER_A','MEMBER');
SQL
out="$(run_session "$MGMT" "$FAMILY_A" 018f0000-0000-7000-8000-000000026403 /tmp/f10-0026-person-family-a.sql)"
expect_line 'PERSON_A=true' "$out"

cat >/tmp/f10-0026-membership-family-b.sql <<SQL
SELECT 'MEMBER_B='||core.add_family_member('$MEMBER_B1','$FAMILY_B','$PERSON','MEMBER');
SELECT 'OVERLAP_DENIED='||core.add_family_member('$MEMBER_B3','$FAMILY_B','$PERSON','PRIMARY');
SELECT 'END_B='||core.end_family_membership('$MEMBER_B1',clock_timestamp()+interval '1 second');
SELECT pg_sleep(1.2);
SELECT 'REJOIN_B='||core.add_family_member('$MEMBER_B2','$FAMILY_B','$PERSON','PRIMARY');
SELECT 'SECOND_CURRENT_DENIED='||core.add_family_member('$MEMBER_B3','$FAMILY_B','$PERSON','MEMBER');
SQL
out="$(run_session "$MGMT" "$FAMILY_B" 018f0000-0000-7000-8000-000000026404 /tmp/f10-0026-membership-family-b.sql)"
for expected in MEMBER_B=true OVERLAP_DENIED=false END_B=true REJOIN_B=true SECOND_CURRENT_DENIED=false; do expect_line "$expected" "$out"; done
membership_catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(*) FROM core.family_memberships WHERE person_id='$PERSON')||'|'||
  (SELECT count(*) FROM core.family_memberships WHERE person_id='$PERSON' AND family_id='$FAMILY_B')||'|'||
  (SELECT count(*) FROM core.family_memberships WHERE person_id='$PERSON' AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp()))")"
test "$membership_catalog" = '3|2|2' || { echo "FAIL membership history=$membership_catalog" >&2; exit 1; }
overlap="$(bootstrap_psql -Atqc "INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from) VALUES('$MEMBER_B3','$FAMILY_B','$PERSON','MEMBER',clock_timestamp())" 2>&1 || true)"
grep -Eq 'family_memberships_no_overlapping_relationship|conflicting key value violates exclusion constraint' <<<"$overlap" || { echo "FAIL overlap constraint=$overlap" >&2; exit 1; }
echo 'PASS one Person has two current Family relationships; ended relationship remains and non-overlapping rejoin succeeds'

cat >/tmp/f10-0026-client-a.sql <<SQL
SELECT 'CLIENT_CREATE='||crm.create_client('$CLIENT_A1','$FAMILY_A','SYN_CLIENT_026A');
SELECT 'CLIENT_DUPLICATE='||crm.create_client('$CLIENT_DUP','$FAMILY_A','SYN_CLIENT_026X');
SELECT 'CLIENT_PAUSE='||crm.transition_client('$CLIENT_A1','PAUSED');
SELECT 'CLIENT_RESUME='||crm.transition_client('$CLIENT_A1','ACTIVE');
SELECT 'CLIENT_END='||crm.transition_client('$CLIENT_A1','ENDED');
SELECT 'CLIENT_REESTABLISH='||crm.create_client('$CLIENT_A2','$FAMILY_A','SYN_CLIENT_026B');
SELECT 'ENDED_REOPEN_DENIED='||crm.transition_client('$CLIENT_A1','ACTIVE');
SELECT 'MISSING_FAMILY='||crm.create_client('$CLIENT_DUP','018f0000-0000-7000-8000-000000026999','SYN_CLIENT_026Z');
SQL
out="$(run_session "$ENTERPRISE" "$FAMILY_A" 018f0000-0000-7000-8000-000000026405 /tmp/f10-0026-client-a.sql)"
for expected in CLIENT_CREATE=true CLIENT_DUPLICATE=false CLIENT_PAUSE=true CLIENT_RESUME=true CLIENT_END=true CLIENT_REESTABLISH=true ENDED_REOPEN_DENIED=false MISSING_FAMILY=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0026-client-cross.sql <<SQL
SELECT 'CROSS_FAMILY='||crm.create_client('$CLIENT_DUP','$FAMILY_A','SYN_CLIENT_026Y');
SQL
out="$(run_session "$ENTERPRISE" "$FAMILY_B" 018f0000-0000-7000-8000-000000026406 /tmp/f10-0026-client-cross.sql)"
expect_line 'CROSS_FAMILY=false' "$out"

cat >/tmp/f10-0026-client-wrong-service.sql <<SQL
SELECT 'WRONG_SERVICE_CLIENT='||crm.create_client('$CLIENT_DUP','$FAMILY_B','SYN_CLIENT_026W');
SQL
out="$(run_session "$MGMT" "$FAMILY_B" 018f0000-0000-7000-8000-000000026407 /tmp/f10-0026-client-wrong-service.sql)"
expect_line 'WRONG_SERVICE_CLIENT=false' "$out"
client_catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(*) FROM crm.clients WHERE family_id='$FAMILY_A')||'|'||
  (SELECT count(*) FROM crm.clients WHERE family_id='$FAMILY_A' AND lifecycle_status='ACTIVE')||'|'||
  (SELECT count(*) FROM crm.clients WHERE family_id='$FAMILY_A' AND lifecycle_status='ENDED')")"
test "$client_catalog" = '2|1|1' || { echo "FAIL client history=$client_catalog" >&2; exit 1; }
echo 'PASS Client remains family-mapped, cross-family/wrong-service writes fail closed, and ended history permits controlled re-establishment'

if app_psql -Atqc "INSERT INTO crm.clients(client_id,family_id,client_code,lifecycle_status,relationship_started_at,created_by_principal_id,updated_by_principal_id) VALUES('$CLIENT_DUP','$FAMILY_B','FORBIDDEN_026','ACTIVE',clock_timestamp(),'$ENTERPRISE','$ENTERPRISE')" >/tmp/f10-0026-acl.out 2>&1; then
  echo 'FAIL app direct CRM INSERT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0026-acl.out
acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','crm.clients','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','crm.clients','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_context_binder','crm.clients','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_function_privilege('public','crm.create_client(uuid,uuid,text)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','crm.create_client(uuid,uuid,text)','EXECUTE')::text")"
test "$acl" = 'false|false|false|false|true' || { echo "FAIL ACL=$acl" >&2; exit 1; }
authority="$(bootstrap_psql -Atqc "SELECT
  (SELECT person_id IS NULL FROM auth.principals WHERE principal_id='$ENTERPRISE')::text||'|'||
  (SELECT family_id='$FAMILY_A'::uuid FROM crm.clients WHERE client_id='$CLIENT_A2')::text||'|'||
  (NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='core' AND table_name='organizations' AND column_name='registration_reference'))::text||'|'||
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='core.family_memberships'::regclass AND conname='family_memberships_no_overlapping_relationship')::text")"
test "$authority" = 'true|true|true|true' || { echo "FAIL canonical authority=$authority" >&2; exit 1; }
audit_counts="$(bootstrap_psql -Atqc "SELECT count(*) FILTER (WHERE decision='ALLOW')||'|'||count(*) FILTER (WHERE decision='DENY') FROM audit.access_events WHERE resource_kind IN ('ORGANIZATION','CRM_CLIENT','FAMILY_MEMBERSHIP')")"
IFS='|' read -r allow_count deny_count <<<"$audit_counts"
test "$allow_count" -gt 0 && test "$deny_count" -gt 0
echo 'PASS 0026 exact ACL, Principal/Person separation, canonical family authority and allow/deny audit regression'

