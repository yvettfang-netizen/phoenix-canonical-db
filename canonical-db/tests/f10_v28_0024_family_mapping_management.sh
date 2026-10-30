#!/usr/bin/env bash
# V1.28 / 0024 permanent regression: controlled proposal, distinct verification,
# immediate revocation and explicit supersession. Synthetic data and split LOGINs only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
MGMT=018f0000-0000-7000-8000-000000002001
REVIEWER=018f0000-0000-7000-8000-000000002009
FAMILY=018f0000-0000-7000-8000-000000000002
ACTOR=018f0000-0000-7000-8000-000000001006
FAMILY_PRINCIPAL=018f0000-0000-7000-8000-000000002006
IDENTITY=018f0000-0000-7000-8000-000000002401
M1=018f0000-0000-7000-8000-000000002402
M2=018f0000-0000-7000-8000-000000002403
M3=018f0000-0000-7000-8000-000000002404
M4=018f0000-0000-7000-8000-000000002405
APP_FAMILY_1=fam_11111111111111111111111111111111
APP_FAMILY_2=fam_22222222222222222222222222222222
APP_FAMILY_3=fam_33333333333333333333333333333333
ISSUER=https://api.phoenix.synthetic.test/canonical-identity
SUBJECT=usr_0024syntheticfamilyprincipal
HASH_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
HASH_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
HASH_C=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
HASH_D=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd

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

proposal_call() {
  local mapping="$1" source="$2" kind="$3" app_family="$4" family="$5" h1="$6" nonce="$7"
  printf "integration.propose_family_mapping('%s','%s','%s','%s','%s','evidence://synthetic/application-ownership/0024','%s','evidence://synthetic/canonical-membership/0024','%s','evidence://synthetic/founder-approval/0024','%s','%s')" \
    "$mapping" "$source" "$kind" "$app_family" "$family" "$h1" "$HASH_B" "$HASH_C" "$nonce"
}

N_PROPOSE_1=018f0000-0000-7000-8000-000000002421
N_VERIFY_1=018f0000-0000-7000-8000-000000002422
N_SAME_REVIEWER=018f0000-0000-7000-8000-000000002423
N_REVOKE_1=018f0000-0000-7000-8000-000000002424
N_PROPOSE_2=018f0000-0000-7000-8000-000000002425
N_VERIFY_2=018f0000-0000-7000-8000-000000002426
N_PROPOSE_3=018f0000-0000-7000-8000-000000002427
N_SUPERSEDE=018f0000-0000-7000-8000-000000002428
N_COLLISION=018f0000-0000-7000-8000-000000002429

cat >/tmp/f10-0024-propose-1.sql <<SQL
SELECT 'IDENTITY='||auth.register_external_identity('$IDENTITY','$ISSUER','$SUBJECT','$FAMILY_PRINCIPAL');
SELECT 'PROPOSE='||$(proposal_call "$M1" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_1" "$FAMILY" "$HASH_A" "$N_PROPOSE_1");
SELECT 'RETRY='||$(proposal_call "$M1" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_1" "$FAMILY" "$HASH_A" "$N_PROPOSE_1");
SELECT 'DRIFT='||$(proposal_call "$M1" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_1" "$FAMILY" "$HASH_D" "$N_PROPOSE_1");
SELECT 'WRONG_SOURCE='||$(proposal_call "$M4" OTHER_SYSTEM FAMILY "$APP_FAMILY_1" "$FAMILY" "$HASH_A" "$N_PROPOSE_1");
SELECT 'WRONG_KIND='||$(proposal_call "$M4" PHOENIX_FAMILY_OS PERSON "$APP_FAMILY_1" "$FAMILY" "$HASH_A" "$N_PROPOSE_1");
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_PROPOSE_1" /tmp/f10-0024-propose-1.sql)"
for expected in IDENTITY=true PROPOSE=true RETRY=true DRIFT=false WRONG_SOURCE=false WRONG_KIND=false; do expect_line "$expected" "$out"; done

cat >/tmp/f10-0024-same-reviewer.sql <<SQL
SELECT 'SAME_REVIEWER='||integration.verify_family_mapping('$M1','$N_SAME_REVIEWER');
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_SAME_REVIEWER" /tmp/f10-0024-same-reviewer.sql)"
expect_line 'SAME_REVIEWER=false' "$out"

cat >/tmp/f10-0024-verify-1.sql <<SQL
SELECT 'VERIFY='||integration.verify_family_mapping('$M1','$N_VERIFY_1');
SELECT 'VERIFY_RETRY='||integration.verify_family_mapping('$M1','$N_VERIFY_1');
SQL
out="$(run_session "$REVIEWER" "$FAMILY" "$N_VERIFY_1" /tmp/f10-0024-verify-1.sql)"
expect_line 'VERIFY=true' "$out"; expect_line 'VERIFY_RETRY=true' "$out"

issued="$(binder_psql -AtF '|' -c "SELECT principal_id,actor_person_id,family_id,ticket_id FROM auth.issue_application_family_context_ticket('$ISSUER','$SUBJECT','$APP_FAMILY_1',clock_timestamp()+interval '45 seconds',gen_random_uuid())")"
IFS='|' read -r got_principal got_actor got_family ticket <<<"$issued"
[ "$got_principal" = "$FAMILY_PRINCIPAL" ] && [ "$got_actor" = "$ACTOR" ] && [ "$got_family" = "$FAMILY" ] && [ -n "$ticket" ] \
  || { echo "FAIL verified resolver output=$issued" >&2; exit 1; }
bound="$(app_psql -AtF '|' -c "SELECT auth.redeem_context_ticket('$ticket','$FAMILY_PRINCIPAL'); SELECT auth.current_principal_id(),auth.current_actor_person_id(),auth.current_family_id(),auth.current_channel(); SELECT auth.clear_context();")"
grep -q "$FAMILY_PRINCIPAL|$ACTOR|$FAMILY|FAMILY" <<<"$bound" || { echo "FAIL verified ticket redeem=$bound" >&2; exit 1; }
echo 'PASS distinct reviewer promoted PENDING mapping and 0023 resolver issued exact family context'

cat >/tmp/f10-0024-revoke-1.sql <<SQL
SELECT 'REVOKE='||integration.revoke_family_mapping('$M1','$N_REVOKE_1');
SELECT 'REVOKE_RETRY='||integration.revoke_family_mapping('$M1','$N_REVOKE_1');
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_REVOKE_1" /tmp/f10-0024-revoke-1.sql)"
expect_line 'REVOKE=true' "$out"; expect_line 'REVOKE_RETRY=true' "$out"
test "$(binder_psql -Atqc "SELECT count(*) FROM auth.issue_application_family_context_ticket('$ISSUER','$SUBJECT','$APP_FAMILY_1',clock_timestamp()+interval '45 seconds',gen_random_uuid())")" = 0
echo 'PASS immediate revoke removed resolver access without second approval'

cat >/tmp/f10-0024-propose-2.sql <<SQL
SELECT 'PROPOSE_2='||$(proposal_call "$M2" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_2" "$FAMILY" "$HASH_A" "$N_PROPOSE_2");
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_PROPOSE_2" /tmp/f10-0024-propose-2.sql)"; expect_line 'PROPOSE_2=true' "$out"
cat >/tmp/f10-0024-verify-2.sql <<SQL
SELECT 'VERIFY_2='||integration.verify_family_mapping('$M2','$N_VERIFY_2');
SQL
out="$(run_session "$REVIEWER" "$FAMILY" "$N_VERIFY_2" /tmp/f10-0024-verify-2.sql)"; expect_line 'VERIFY_2=true' "$out"
cat >/tmp/f10-0024-propose-3.sql <<SQL
SELECT 'PROPOSE_3='||$(proposal_call "$M3" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_3" "$FAMILY" "$HASH_A" "$N_PROPOSE_3");
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_PROPOSE_3" /tmp/f10-0024-propose-3.sql)"; expect_line 'PROPOSE_3=true' "$out"
cat >/tmp/f10-0024-supersede.sql <<SQL
SELECT 'SUPERSEDE='||integration.supersede_family_mapping('$M2','$M3','$N_SUPERSEDE');
SELECT 'SUPERSEDE_RETRY='||integration.supersede_family_mapping('$M2','$M3','$N_SUPERSEDE');
SQL
out="$(run_session "$REVIEWER" "$FAMILY" "$N_SUPERSEDE" /tmp/f10-0024-supersede.sql)"
expect_line 'SUPERSEDE=true' "$out"; expect_line 'SUPERSEDE_RETRY=true' "$out"

cat >/tmp/f10-0024-collision.sql <<SQL
SELECT 'COLLISION='||$(proposal_call "$M4" PHOENIX_FAMILY_OS FAMILY "$APP_FAMILY_3" "$FAMILY" "$HASH_A" "$N_COLLISION");
SQL
out="$(run_session "$MGMT" "$FAMILY" "$N_COLLISION" /tmp/f10-0024-collision.sql)"; expect_line 'COLLISION=false' "$out"
test "$(binder_psql -Atqc "SELECT count(*) FROM auth.issue_application_family_context_ticket('$ISSUER','$SUBJECT','$APP_FAMILY_2',clock_timestamp()+interval '45 seconds',gen_random_uuid())")" = 0
test "$(binder_psql -Atqc "SELECT count(*) FROM auth.issue_application_family_context_ticket('$ISSUER','$SUBJECT','$APP_FAMILY_3',clock_timestamp()+interval '45 seconds',gen_random_uuid())")" = 1
echo 'PASS explicit supersession denied old application family ID and enabled only replacement'

# A family with only an expired membership is not eligible for proposal.
EXPIRED_FAMILY=018f0000-0000-7000-8000-000000002410
EXPIRED_PERSON=018f0000-0000-7000-8000-000000002411
EXPIRED_MEMBER=018f0000-0000-7000-8000-000000002412
N_EXPIRED=018f0000-0000-7000-8000-000000002430
bootstrap_psql -At <<SQL >/dev/null
INSERT INTO core.families(family_id,display_name) VALUES('$EXPIRED_FAMILY','Synthetic expired-membership family');
INSERT INTO core.people(person_id,display_name) VALUES('$EXPIRED_PERSON','Synthetic expired member');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from,valid_until)
VALUES('$EXPIRED_MEMBER','$EXPIRED_FAMILY','$EXPIRED_PERSON','PRIMARY',clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day');
SQL
cat >/tmp/f10-0024-expired.sql <<SQL
SELECT 'EXPIRED_MEMBERSHIP='||$(proposal_call "$M4" PHOENIX_FAMILY_OS FAMILY fam_44444444444444444444444444444444 "$EXPIRED_FAMILY" "$HASH_A" "$N_EXPIRED");
SQL
out="$(run_session "$MGMT" "$EXPIRED_FAMILY" "$N_EXPIRED" /tmp/f10-0024-expired.sql)"; expect_line 'EXPIRED_MEMBERSHIP=false' "$out"

MISSING_FAMILY=018f0000-0000-7000-8000-000000002499
missing_out="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$MGMT',NULL,'$MISSING_FAMILY','INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$MGMT')" 2>&1 || true)"
grep -q 'CONTEXT_FAMILY_INVALID' <<<"$missing_out" || { echo "FAIL missing family=$missing_out" >&2; exit 1; }
INACTIVE=018f0000-0000-7000-8000-000000002413
test "$(bootstrap_psql -Atqc "SELECT auth.install_service_principal('$INACTIVE','Synthetic inactive mapping service')")" = t
test "$(bootstrap_psql -Atqc "SELECT auth.disable_service_principal('$INACTIVE')")" = t
inactive_out="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$INACTIVE',NULL,'$FAMILY','INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$INACTIVE')" 2>&1 || true)"
grep -q 'CONTEXT_PRINCIPAL_INVALID' <<<"$inactive_out" || { echo "FAIL inactive principal=$inactive_out" >&2; exit 1; }
echo 'PASS missing family, expired membership and inactive SERVICE principal fail closed'

no_context="$(app_psql -Atqc "SELECT $(proposal_call "$M4" PHOENIX_FAMILY_OS FAMILY fam_55555555555555555555555555555555 "$FAMILY" "$HASH_A" 018f0000-0000-7000-8000-000000002431)")"
test "$no_context" = f || { echo "FAIL no-context proposal=$no_context" >&2; exit 1; }
if app_psql -Atqc "INSERT INTO integration.legacy_id_mappings(mapping_id,source_system,entity_kind,legacy_id,canonical_id,mapping_status,evidence_ref) VALUES('$M4','PHOENIX_FAMILY_OS','FAMILY','fam_66666666666666666666666666666666','$FAMILY','PENDING','forbidden')" >/tmp/f10-0024-acl.out 2>&1; then
  echo 'FAIL app direct mapping insert accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0024-acl.out
binder_acl="$(binder_psql -Atqc "SELECT $(proposal_call "$M4" PHOENIX_FAMILY_OS FAMILY fam_77777777777777777777777777777777 "$FAMILY" "$HASH_A" 018f0000-0000-7000-8000-000000002432)" 2>&1 || true)"
grep -q 'permission denied' <<<"$binder_acl" || { echo "FAIL binder ACL=$binder_acl" >&2; exit 1; }

acl="$(bootstrap_psql -Atqc "SELECT
  has_function_privilege('phoenix_canonical_app','integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_context_binder','integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_reader','integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('public','integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')::text")"
test "$acl" = 'true|false|false|false' || { echo "FAIL function ACL=$acl" >&2; exit 1; }
table_acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_context_binder','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('public','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')::text")"
test "$table_acl" = 'false|false|false|false' || { echo "FAIL table ACL=$table_acl" >&2; exit 1; }
lock_order="$(bootstrap_psql -Atqc "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='integration' AND p.proname IN ('propose_family_mapping','verify_family_mapping','revoke_family_mapping','supersede_family_mapping') AND position('auth.is_internal_service()' in pg_get_functiondef(p.oid)) < position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))")"
test "$lock_order" = 4 || { echo "FAIL authorization-before-lock count=$lock_order" >&2; exit 1; }
echo 'PASS unauthorized callers are rejected before the 0025 serialization lock'

terminal_update="$(bootstrap_psql -Atqc "UPDATE integration.legacy_id_mappings SET application_ownership_evidence_sha256='$HASH_D' WHERE mapping_id='$M1'" 2>&1 || true)"
grep -q 'MANAGED_FAMILY_MAPPING_IMMUTABLE_FIELDS' <<<"$terminal_update" || { echo "FAIL terminal update=$terminal_update" >&2; exit 1; }
terminal_delete="$(bootstrap_psql -Atqc "DELETE FROM integration.legacy_id_mappings WHERE mapping_id='$M1'" 2>&1 || true)"
grep -q 'MANAGED_FAMILY_MAPPING_DELETE_DENIED' <<<"$terminal_delete" || { echo "FAIL terminal delete=$terminal_delete" >&2; exit 1; }

catalog="$(bootstrap_psql -Atqc "SELECT mapping_status||'|'||(proposed_by_principal_id<>decided_by_principal_id)::text FROM integration.legacy_id_mappings WHERE mapping_id IN ('$M1','$M2','$M3') ORDER BY mapping_id; SELECT 'ALLOW='||count(*) FROM audit.access_events WHERE resource_kind='FAMILY_MAPPING' AND decision='ALLOW'; SELECT 'DENY='||count(*) FROM audit.access_events WHERE resource_kind='FAMILY_MAPPING' AND decision='DENY';")"
grep -qx 'REVOKED|true' <<<"$catalog"
grep -qx 'SUPERSEDED|true' <<<"$catalog"
grep -qx 'VERIFIED|true' <<<"$catalog"
grep -Eq '^ALLOW=[1-9][0-9]*$' <<<"$catalog"
grep -Eq '^DENY=[1-9][0-9]*$' <<<"$catalog"
echo 'PASS 0024 split LOGIN, one-use SERVICE context, evidence drift, dual review, revoke, supersede, ACL, immutability and audit regression'

