#!/usr/bin/env bash
# V1.25 / 0023 permanent regression: the binder resolves the authenticated
# application subject and VERIFIED Phoenix Family OS family mapping and issues a
# one-use ticket in one database call. Synthetic data and separate LOGINs only.
set -euo pipefail

app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap            -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }

FAMILY=018f0000-0000-7000-8000-000000000001
ACTOR=018f0000-0000-7000-8000-000000002301
MEMBERSHIP=018f0000-0000-7000-8000-000000002302
PRINCIPAL=018f0000-0000-7000-8000-000000002303
IDENTITY=018f0000-0000-7000-8000-000000002304
MAPPING=018f0000-0000-7000-8000-000000002305
ISSUER=https://api.phoenix.synthetic.test/canonical-identity
SUBJECT=usr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
APP_FAMILY=fam_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

bootstrap_psql <<SQL
INSERT INTO core.people(person_id,display_name)
VALUES('$ACTOR','Synthetic 0023 Family Actor');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from)
VALUES('$MEMBERSHIP','$FAMILY','$ACTOR','MEMBER',clock_timestamp()-interval '1 minute');
INSERT INTO auth.principals(principal_id,person_id,principal_kind,status)
VALUES('$PRINCIPAL','$ACTOR','FAMILY','ACTIVE');
INSERT INTO auth.external_identities(
  external_identity_id,issuer,subject,principal_id,status,created_by_principal_id
) VALUES(
  '$IDENTITY','$ISSUER','$SUBJECT','$PRINCIPAL','ACTIVE',
  '018f0000-0000-7000-8000-000000002001'
);
INSERT INTO integration.legacy_id_mappings(
  mapping_id,source_system,entity_kind,legacy_id,canonical_id,
  mapping_status,evidence_ref,decided_by,decided_at
) VALUES(
  '$MAPPING','PHOENIX_FAMILY_OS','FAMILY','$APP_FAMILY','$FAMILY',
  'VERIFIED','synthetic/evidence/0023','$ACTOR',clock_timestamp()
);

-- These negative rows prove that a different source, non-VERIFIED status,
-- expired membership, disabled identity and non-FAMILY principal do not pass.
INSERT INTO integration.legacy_id_mappings(
  mapping_id,source_system,entity_kind,legacy_id,canonical_id,mapping_status,evidence_ref,decided_by,decided_at
) VALUES
('018f0000-0000-7000-8000-000000002311','OTHER_SYSTEM','FAMILY','fam_cccccccccccccccccccccccccccccccc','$FAMILY','VERIFIED','synthetic/other-source','$ACTOR',clock_timestamp()),
('018f0000-0000-7000-8000-000000002312','PHOENIX_FAMILY_OS','FAMILY','fam_dddddddddddddddddddddddddddddddd','$FAMILY','PENDING','synthetic/pending',NULL,NULL),
('018f0000-0000-7000-8000-000000002313','PHOENIX_FAMILY_OS','FAMILY','fam_eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','$FAMILY','REVOKED','synthetic/revoked',NULL,NULL);
SQL

count_rows() {
  binder_psql -Atqc "SELECT count(*) FROM auth.issue_application_family_context_ticket(
    '$1','$2','$3',clock_timestamp()+interval '45 seconds',gen_random_uuid())"
}
check_zero() {
  local label="$1" issuer="$2" subject="$3" family="$4" value
  value="$(count_rows "$issuer" "$subject" "$family")"
  [ "$value" = 0 ] && echo "PASS $label denied" || { echo "FAIL $label rows=$value"; exit 1; }
}

echo '=== 0023 binder-only atomic application family context'
issued="$(binder_psql -AtF '|' -c "SELECT principal_id,actor_person_id,family_id,ticket_id
  FROM auth.issue_application_family_context_ticket(
    '$ISSUER','$SUBJECT','$APP_FAMILY',clock_timestamp()+interval '45 seconds',gen_random_uuid())")"
IFS='|' read -r got_principal got_actor got_family ticket <<<"$issued"
[ "$got_principal" = "$PRINCIPAL" ] && [ "$got_actor" = "$ACTOR" ] && [ "$got_family" = "$FAMILY" ] && [ -n "$ticket" ] \
  && echo 'PASS atomic resolver returned principal, actor, family and ticket' \
  || { echo "FAIL atomic output=$issued"; exit 1; }

bound="$(app_psql -AtF '|' -c "SELECT auth.redeem_context_ticket('$ticket','$PRINCIPAL');
SELECT auth.current_principal_id(),auth.current_actor_person_id(),auth.current_family_id(),auth.current_channel();
SELECT auth.clear_context();")"
grep -q "$PRINCIPAL|$ACTOR|$FAMILY|FAMILY" <<<"$bound" \
  && echo 'PASS separate app LOGIN redeemed exact FAMILY context' \
  || { echo "FAIL redeemed output=$bound"; exit 1; }

reuse="$(app_psql -v ON_ERROR_STOP=1 -Atqc "SELECT auth.redeem_context_ticket('$ticket','$PRINCIPAL')" 2>&1 || true)"
grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED' <<<"$reuse" \
  && echo 'PASS one-use ticket reuse denied' || { echo "FAIL reuse=$reuse"; exit 1; }

check_zero UNKNOWN_SUBJECT "$ISSUER" usr_unknown_0023 "$APP_FAMILY"
check_zero WRONG_FAMILY "$ISSUER" "$SUBJECT" fam_ffffffffffffffffffffffffffffffff
check_zero WRONG_SOURCE "$ISSUER" "$SUBJECT" fam_cccccccccccccccccccccccccccccccc
check_zero PENDING_MAPPING "$ISSUER" "$SUBJECT" fam_dddddddddddddddddddddddddddddddd
check_zero REVOKED_MAPPING "$ISSUER" "$SUBJECT" fam_eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
check_zero MALFORMED_SUBJECT "$ISSUER" openid-sensitive-value "$APP_FAMILY"
check_zero MALFORMED_FAMILY "$ISSUER" "$SUBJECT" 018f0000-0000-7000-8000-000000000001

bootstrap_psql -c "UPDATE core.family_memberships SET valid_until=clock_timestamp()-interval '1 second' WHERE membership_id='$MEMBERSHIP'"
check_zero EXPIRED_MEMBERSHIP "$ISSUER" "$SUBJECT" "$APP_FAMILY"
bootstrap_psql -c "UPDATE core.family_memberships SET valid_until=NULL WHERE membership_id='$MEMBERSHIP'; UPDATE auth.external_identities SET status='DISABLED',disabled_at=clock_timestamp() WHERE external_identity_id='$IDENTITY'"
check_zero DISABLED_IDENTITY "$ISSUER" "$SUBJECT" "$APP_FAMILY"

app_acl="$(app_psql -Atqc "SELECT count(*) FROM auth.issue_application_family_context_ticket('$ISSUER','$SUBJECT','$APP_FAMILY',clock_timestamp()+interval '45 seconds',gen_random_uuid())" 2>&1 || true)"
grep -q 'permission denied' <<<"$app_acl" && echo 'PASS app cannot execute binder resolver' \
  || { echo "FAIL app ACL=$app_acl"; exit 1; }
[ "$(bootstrap_psql -Atqc "SELECT has_function_privilege('public','auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)','EXECUTE')")" = f ] \
  && echo 'PASS PUBLIC execute revoked' || { echo 'FAIL PUBLIC function ACL'; exit 1; }
[ "$(bootstrap_psql -Atqc "SELECT has_function_privilege('phoenix_canonical_context_binder','auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)','EXECUTE')")" = t ] \
  && echo 'PASS binder execute granted' || { echo 'FAIL binder function ACL'; exit 1; }

echo 'PASS 0023 fixed source authority, VERIFIED mapping, current membership, split LOGIN, one-use ticket and ACL regression'
