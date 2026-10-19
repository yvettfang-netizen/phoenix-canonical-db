#!/usr/bin/env bash
# 0018 D-2 permanent regression. Runs after the F10 seed has created separate LOGIN roles.
set -euo pipefail
umask 077

binder() {
  PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -At -h 127.0.0.1 \
    -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}
app() {
  PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -At -h 127.0.0.1 \
    -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}

echo '== 0018 D-2 capability catalog using separate LOGIN accounts'
binder_acl="$(binder -c "SELECT
  'legacy_bind='||has_function_privilege(current_user,'auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE')||
  '|issue_ticket='||has_function_privilege(current_user,'auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid)','EXECUTE')||
  '|resolve_identity='||has_function_privilege(current_user,'auth.resolve_external_identity(text,text)','EXECUTE');")"
echo "$binder_acl"
[ "$binder_acl" = 'legacy_bind=false|issue_ticket=true|resolve_identity=true' ] || {
  echo 'FAIL binder capability catalog'; exit 1;
}
echo 'PASS binder cannot call legacy bind and retains ticket/identity capabilities'

app_acl="$(app -c "SELECT
  'redeem_ticket='||has_function_privilege(current_user,'auth.redeem_context_ticket(uuid,uuid)','EXECUTE')||
  '|clear_context='||has_function_privilege(current_user,'auth.clear_context()','EXECUTE');")"
echo "$app_acl"
[ "$app_acl" = 'redeem_ticket=true|clear_context=true' ] || {
  echo 'FAIL app context capability catalog'; exit 1;
}
echo 'PASS app retains redeem and clear capabilities'

echo '== direct legacy bind must be rejected by PostgreSQL privilege checking'
if denied="$(binder -c "SELECT auth.bind_context(NULL,NULL,NULL,'INTERNAL',clock_timestamp()+interval '30 seconds',gen_random_uuid());" 2>&1)"; then
  echo "$denied"
  echo 'FAIL binder direct legacy bind unexpectedly succeeded'
  exit 1
fi
echo "$denied" | tail -3
grep -qi 'permission denied for function bind_context' <<<"$denied" || {
  echo 'FAIL binder direct call failed for an unexpected reason'; exit 1;
}
echo 'PASS binder direct legacy bind rejected with permission denied'
