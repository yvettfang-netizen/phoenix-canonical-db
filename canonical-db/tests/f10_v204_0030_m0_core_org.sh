#!/usr/bin/env bash
# M0 permanent regression. Synthetic data and split LOGIN accounts only.
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
MGMT=018f0000-0000-7000-8000-000000002001
ENTERPRISE=018f0000-0000-7000-8000-000000002026
ORG_A=018f0000-0000-7000-8000-000000026201
ORG_B=018f0000-0000-7000-8000-000000030201
ORG_DUP=018f0000-0000-7000-8000-000000030202
NAME_HISTORY=018f0000-0000-7000-8000-000000030211
NAME_EVENT=018f0000-0000-7000-8000-000000030212
IDENT_A=018f0000-0000-7000-8000-000000030221
IDENT_DUP=018f0000-0000-7000-8000-000000030222
IDENT_REUSE=018f0000-0000-7000-8000-000000030223
IDENT_EVENT=018f0000-0000-7000-8000-000000030224
IDENT_REVOKE_EVENT=018f0000-0000-7000-8000-000000030225
IDENT_REUSE_EVENT=018f0000-0000-7000-8000-000000030226
REL_A=018f0000-0000-7000-8000-000000030231
REL_DUP=018f0000-0000-7000-8000-000000030232
REL_REJOIN=018f0000-0000-7000-8000-000000030233
REL_EVENT=018f0000-0000-7000-8000-000000030234
REL_END_EVENT=018f0000-0000-7000-8000-000000030235
REL_REJOIN_EVENT=018f0000-0000-7000-8000-000000030236
DIGEST=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U "$APP"    -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local principal="$1" nonce="$2" file="$3" ticket
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',NULL,NULL,'INTERNAL',clock_timestamp()+interval '45 seconds','$nonce','$principal')")"
  {
    printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

cat >/tmp/f10-0030-org.sql <<SQL
SELECT 'ORG_B='||core.register_organization('$ORG_B','Synthetic Global Institute Ltd','Synthetic Global Institute','UNIVERSITY','GB',NULL);
SELECT 'RENAME='||core.rename_organization('$ORG_A','$NAME_HISTORY','Synthetic Phoenix Academy Ltd','Synthetic Phoenix Academy','$NAME_EVENT');
SELECT 'IDENT_A='||core.register_organization_identifier('$IDENT_A','$ORG_A','BUSINESS_REGISTRATION','CN','Synthetic Registry','$DIGEST',NULL,'$IDENT_EVENT');
SELECT 'IDENT_DUP='||core.register_organization_identifier('$IDENT_DUP','$ORG_B','BUSINESS_REGISTRATION','CN','Synthetic Registry','$DIGEST',NULL,'$IDENT_REUSE_EVENT');
SELECT 'IDENT_REVOKE='||core.revoke_organization_identifier('$IDENT_A','$IDENT_REVOKE_EVENT');
SELECT 'IDENT_REUSE='||core.register_organization_identifier('$IDENT_REUSE','$ORG_B','BUSINESS_REGISTRATION','CN','Synthetic Registry','$DIGEST',NULL,'$IDENT_REUSE_EVENT');
SELECT 'REL_A='||core.create_organization_relationship('$REL_A','$ORG_A','$ORG_B','PARTNER',NULL,'$REL_EVENT');
SELECT 'REL_DUP='||core.create_organization_relationship('$REL_DUP','$ORG_A','$ORG_B','PARTNER',NULL,'$REL_REJOIN_EVENT');
SELECT 'REL_END='||core.end_organization_relationship('$REL_A','$REL_END_EVENT');
SELECT 'REL_REJOIN='||core.create_organization_relationship('$REL_REJOIN','$ORG_A','$ORG_B','PARTNER',NULL,'$REL_REJOIN_EVENT');
SQL
out="$(run_session "$ENTERPRISE" 018f0000-0000-7000-8000-000000030401 /tmp/f10-0030-org.sql)"
for expected in ORG_B=true RENAME=true IDENT_A=true IDENT_DUP=false IDENT_REVOKE=true IDENT_REUSE=true REL_A=true REL_DUP=false REL_END=true REL_REJOIN=true; do
  expect_line "$expected" "$out"
done

cat >/tmp/f10-0030-wrong-service.sql <<SQL
SELECT 'WRONG_SERVICE='||core.register_organization('$ORG_DUP','Forbidden Organization','Forbidden Organization','ENTERPRISE','CN',NULL);
SQL
out="$(run_session "$MGMT" 018f0000-0000-7000-8000-000000030402 /tmp/f10-0030-wrong-service.sql)"
expect_line 'WRONG_SERVICE=false' "$out"

catalog="$(bootstrap_psql -Atqc "SELECT
  (SELECT count(*) FROM integration.public_ids WHERE entity_kind='ORGANIZATION')||'|'||
  (SELECT count(*) FROM core.organization_name_history WHERE organization_id='$ORG_A')||'|'||
  (SELECT count(*) FROM core.organization_identifiers WHERE identifier_digest='$DIGEST')||'|'||
  (SELECT count(*) FROM core.organization_relationships WHERE source_organization_id='$ORG_A' AND target_organization_id='$ORG_B')||'|'||
  (SELECT count(*) FROM core.organization_events WHERE organization_id='$ORG_A')")"
test "$catalog" = '2|2|2|2|9' || { echo "FAIL M0 catalog=$catalog" >&2; exit 1; }

if app_psql -Atqc "INSERT INTO core.organization_identifiers(organization_identifier_id,organization_id,identifier_type,issuing_country_code,issuer_name,identifier_digest,status,valid_from,created_by_principal_id) VALUES('$IDENT_DUP','$ORG_A','TAX','CN','Forbidden','$DIGEST','ACTIVE',clock_timestamp(),'$ENTERPRISE')" >/tmp/f10-0030-acl.out 2>&1; then
  echo 'FAIL app direct Organization identifier INSERT accepted' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0030-acl.out

acl="$(bootstrap_psql -Atqc "SELECT
  has_table_privilege('phoenix_canonical_app','core.organization_identifiers','SELECT,INSERT,UPDATE,DELETE')::text||'|'||
  has_table_privilege('phoenix_canonical_reader','core.organization_relationships','SELECT')::text||'|'||
  has_table_privilege('phoenix_canonical_context_binder','core.organization_events','SELECT')::text||'|'||
  has_function_privilege('public','core.rename_organization(uuid,uuid,text,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','core.rename_organization(uuid,uuid,text,text,uuid)','EXECUTE')::text||'|'||
  has_function_privilege('phoenix_canonical_app','core.transition_organization(uuid,text)','EXECUTE')::text")"
test "$acl" = 'false|false|false|false|true|false' || { echo "FAIL M0 ACL=$acl" >&2; exit 1; }

immutable="$(bootstrap_psql -Atqc "UPDATE core.organization_events SET reason_code='FORBIDDEN' WHERE organization_event_id='$NAME_EVENT'" 2>&1 || true)"
grep -q 'ORGANIZATION_HISTORY_IMMUTABLE' <<<"$immutable" || { echo "FAIL event mutation=$immutable" >&2; exit 1; }
echo 'PASS M0 Organization identifiers, relationships, name history, public IDs, exact ACL and immutable events'
