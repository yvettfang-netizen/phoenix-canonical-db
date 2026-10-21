#!/usr/bin/env bash
set -euo pipefail
umask 077

APP=phoenix_canonical_app_f10
BINDER=phoenix_canonical_binder_f10
DB=phoenix_canonical_dev
OPS_P=018f0000-0000-7000-8000-000000002009
MGMT_P=018f0000-0000-7000-8000-000000002001
G_P=018f0000-0000-7000-8000-000000002002
ADV_P=018f0000-0000-7000-8000-000000002004
G=018f0000-0000-7000-8000-000000001002
ADV=018f0000-0000-7000-8000-000000001004
FA=018f0000-0000-7000-8000-000000000001
FB=018f0000-0000-7000-8000-000000000002
STUA=018f0000-0000-7000-8000-000000001003
STUB=018f0000-0000-7000-8000-000000001006
COURSE=018f0000-0000-7000-8000-000000021101
OTHER_COURSE=018f0000-0000-7000-8000-000000021102
EXPIRED_COURSE=018f0000-0000-7000-8000-000000021103
FUTURE_COURSE=018f0000-0000-7000-8000-000000021104

app_psql() { PGPASSFILE=/tmp/f10-app.pgpass psql -X -qAt -h 127.0.0.1 -U "$APP" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -qAt -h 127.0.0.1 -U "$BINDER" -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -qAt -h 127.0.0.1 -U phoenix_bootstrap -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
run_session() {
  local principal="$1" actor="$2" family="$3" channel="$4" file="$5" ticket actor_sql family_sql
  actor_sql=NULL; family_sql=NULL
  [ "$actor" = NULL ] || actor_sql="'$actor'::uuid"
  [ "$family" = NULL ] || family_sql="'$family'::uuid"
  ticket="$(binder_psql -c "SELECT auth.issue_context_ticket('$principal',$actor_sql,$family_sql,'$channel',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$principal')")"
  {
    printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$principal"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL missing [%s]\n%s\n' "$1" "$2" >&2; exit 1; }; }

consent_before="$(bootstrap_psql -c "SELECT count(*) FROM consent.grants WHERE subject_person_id='$STUA'")"

cat >/tmp/f10-0021-grant.sql <<SQL
SELECT 'EDU='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021001','phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-grant-1',1,
 '$FA','$STUA','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:00 UTC');
SELECT 'COURSE='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021002','phoenix_operations','synthetic-ent-course-1','synthetic-event-course-grant-1',1,
 '$FA','$STUA','COURSE','$COURSE','2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:01 UTC');
SELECT 'ASKWISE='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021003','phoenix_operations','synthetic-ent-askwise-1','synthetic-event-askwise-grant-1',1,
 '$FA','$STUA','ASKWISE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:02 UTC');
SELECT 'EXPIRED='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021004','phoenix_operations','synthetic-ent-expired-1','synthetic-event-expired-grant-1',1,
 '$FA','$STUA','COURSE','$EXPIRED_COURSE','2020-01-01 UTC','2021-01-01 UTC','2020-01-01 UTC');
SELECT 'FUTURE='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021005','phoenix_operations','synthetic-ent-future-1','synthetic-event-future-grant-1',1,
 '$FA','$STUA','COURSE','$FUTURE_COURSE','2098-01-01 UTC','2099-01-01 UTC','2026-10-20 07:03 UTC');
SELECT 'IDEMPOTENT='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021001','phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-grant-1',1,
 '$FA','$STUA','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:00 UTC');
SELECT 'EVENT_CONFLICT='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021099','phoenix_operations','synthetic-ent-conflict','synthetic-event-edu-grant-1',1,
 '$FA','$STUA','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:00 UTC');
SELECT 'WRONG_SOURCE='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021096','other_operations','synthetic-ent-wrong-source','synthetic-event-wrong-source',1,
 '$FA','$STUA','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:04 UTC');
SELECT 'CROSS_FAMILY='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021097','phoenix_operations','synthetic-ent-cross-family','synthetic-event-cross-family',1,
 '$FA','$STUB','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:05 UTC');
SQL
grant_out="$(run_session "$OPS_P" NULL "$FA" INTERNAL /tmp/f10-0021-grant.sql)"
for expected in EDU=true COURSE=true ASKWISE=true EXPIRED=true FUTURE=true IDEMPOTENT=true EVENT_CONFLICT=false WRONG_SOURCE=false CROSS_FAMILY=false; do
  expect_line "$expected" "$grant_out"
done

cat >/tmp/f10-0021-check.sql <<SQL
SELECT 'EDU='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','EDUCATION_SERVICE',NULL);
SELECT 'COURSE='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE','$COURSE');
SELECT 'COURSE_SCOPE='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE','$OTHER_COURSE');
SELECT 'ASKWISE='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','ASKWISE',NULL);
SELECT 'PRODUCT_SEPARATION='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE',NULL);
SELECT 'EXPIRED='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE','$EXPIRED_COURSE');
SELECT 'FUTURE='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE','$FUTURE_COURSE');
SELECT 'HAS_VALID='||operations_ref.has_valid_entitlement('$FA','$STUA','COURSE','$COURSE');
SQL
check_out="$(run_session "$G_P" "$G" "$FA" FAMILY /tmp/f10-0021-check.sql)"
expect_line 'EDU=true|ENTITLEMENT_ACTIVE' "$check_out"
expect_line 'COURSE=true|ENTITLEMENT_ACTIVE' "$check_out"
expect_line 'COURSE_SCOPE=false|ENTITLEMENT_MISSING' "$check_out"
expect_line 'ASKWISE=true|ENTITLEMENT_ACTIVE' "$check_out"
expect_line 'PRODUCT_SEPARATION=false|ENTITLEMENT_MISSING' "$check_out"
expect_line 'EXPIRED=false|ENTITLEMENT_EXPIRED' "$check_out"
expect_line 'FUTURE=false|ENTITLEMENT_NOT_YET_VALID' "$check_out"
expect_line 'HAS_VALID=true' "$check_out"

cat >/tmp/f10-0021-advisor.sql <<SQL
SELECT 'ADVISOR='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','EDUCATION_SERVICE',NULL);
SQL
advisor_out="$(run_session "$ADV_P" "$ADV" "$FA" ADVISOR /tmp/f10-0021-advisor.sql)"
expect_line 'ADVISOR=false|CONTEXT_OR_SUBJECT_DENIED' "$advisor_out"

cat >/tmp/f10-0021-wrong-service.sql <<SQL
SELECT 'WRONG_SERVICE='||operations_ref.register_entitlement(
 '018f0000-0000-7000-8000-000000021098','phoenix_operations','synthetic-ent-wrong-service','synthetic-event-wrong-service',1,
 '$FA','$STUA','EDUCATION_SERVICE',NULL,'2020-01-01 UTC','2090-01-01 UTC','2026-10-20 07:06 UTC');
SQL
wrong_service_out="$(run_session "$MGMT_P" NULL "$FA" INTERNAL /tmp/f10-0021-wrong-service.sql)"
expect_line 'WRONG_SERVICE=false' "$wrong_service_out"

cat >/tmp/f10-0021-revoke.sql <<SQL
SELECT 'OUT_OF_ORDER='||operations_ref.revoke_entitlement('phoenix_operations','synthetic-ent-course-1','synthetic-event-course-revoke-old',1,'2026-10-20 07:09 UTC');
SELECT 'REVOKE='||operations_ref.revoke_entitlement('phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-revoke-1',2,'2026-10-20 07:10 UTC');
SELECT 'REVOKE_IDEMPOTENT='||operations_ref.revoke_entitlement('phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-revoke-1',2,'2026-10-20 07:10 UTC');
SELECT 'REVOKE_CONFLICT='||operations_ref.revoke_entitlement('phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-revoke-1',3,'2026-10-20 07:10 UTC');
SELECT 'REVOKE_TERMINAL='||operations_ref.revoke_entitlement('phoenix_operations','synthetic-ent-edu-1','synthetic-event-edu-revoke-2',3,'2026-10-20 07:11 UTC');
SELECT 'EXPIRED_COUNT='||operations_ref.expire_entitlements();
SQL
revoke_out="$(run_session "$OPS_P" NULL "$FA" INTERNAL /tmp/f10-0021-revoke.sql)"
for expected in OUT_OF_ORDER=false REVOKE=true REVOKE_IDEMPOTENT=true REVOKE_CONFLICT=false REVOKE_TERMINAL=false EXPIRED_COUNT=1; do
  expect_line "$expected" "$revoke_out"
done

cat >/tmp/f10-0021-post.sql <<SQL
SELECT 'REVOKED='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','EDUCATION_SERVICE',NULL);
SELECT 'COURSE_STILL_ACTIVE='||allowed||'|'||reason_code FROM operations_ref.check_entitlement('$FA','$STUA','COURSE','$COURSE');
SQL
post_out="$(run_session "$G_P" "$G" "$FA" FAMILY /tmp/f10-0021-post.sql)"
expect_line 'REVOKED=false|ENTITLEMENT_REVOKED' "$post_out"
expect_line 'COURSE_STILL_ACTIVE=true|ENTITLEMENT_ACTIVE' "$post_out"

consent_after="$(bootstrap_psql -c "SELECT count(*) FROM consent.grants WHERE subject_person_id='$STUA'")"
[ "$consent_before" = "$consent_after" ] || { echo 'FAIL entitlement changed Consent rows' >&2; exit 1; }

if app_psql -c 'SELECT count(*) FROM operations_ref.entitlement_ref' >/tmp/f10-0021-direct.out 2>&1; then
  echo 'FAIL app read raw entitlement table' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0021-direct.out
if app_psql -c "INSERT INTO operations_ref.entitlement_event(source_system,source_event_id,entitlement_ref_id,event_kind,source_version,occurred_at,recorded_by_principal_id) VALUES ('phoenix_operations','forbidden','018f0000-0000-7000-8000-000000021001','REVOKE',99,clock_timestamp(),'$OPS_P')" >/tmp/f10-0021-direct.out 2>&1; then
  echo 'FAIL app direct event insert' >&2; exit 1
fi
grep -q 'permission denied' /tmp/f10-0021-direct.out

if bootstrap_psql -c "UPDATE operations_ref.entitlement_ref SET status='ACTIVE',revoked_at=NULL WHERE entitlement_ref_id='018f0000-0000-7000-8000-000000021001'" >/tmp/f10-0021-trigger.out 2>&1; then
  echo 'FAIL revoked entitlement reactivated' >&2; exit 1
fi
grep -q 'ENTITLEMENT_TERMINAL_STATE_IMMUTABLE' /tmp/f10-0021-trigger.out
if bootstrap_psql -c "UPDATE operations_ref.entitlement_event SET source_version=99 WHERE source_system='phoenix_operations' AND source_event_id='synthetic-event-edu-grant-1'" >/tmp/f10-0021-trigger.out 2>&1; then
  echo 'FAIL entitlement event mutated' >&2; exit 1
fi
grep -q 'ENTITLEMENT_EVENT_IMMUTABLE' /tmp/f10-0021-trigger.out

acl="$(bootstrap_psql -c "SELECT (NOT has_function_privilege('public','operations_ref.is_operations_service()','EXECUTE') AND NOT has_function_privilege('public','operations_ref.protect_entitlement_ref()','EXECUTE') AND NOT has_function_privilege('public','operations_ref.protect_entitlement_event()','EXECUTE') AND NOT has_table_privilege('phoenix_canonical_app','operations_ref.entitlement_ref','SELECT') AND NOT has_table_privilege('phoenix_canonical_app','operations_ref.entitlement_ref','INSERT'))")"
[ "$acl" = t ] || { echo 'FAIL Operations ACL boundary' >&2; exit 1; }

echo 'PASS 0021 Operations entitlement source, idempotency, ordering, tenant, product, expiry, revocation, Consent and ACL regression'

