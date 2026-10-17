#!/usr/bin/env bash
# V1.8 / 0017 permanent regression (FD-6 local part):
#  - external identity mapping: SERVICE-only management, binder-only resolution, no auto-provisioning,
#    disabled mapping or principal stops resolving;
#  - request number (ticket request_nonce) reaches the audit row (the runner checks the server log);
#  - connection-pool conformance on one backend: clear_context removes all visibility and write rights,
#    re-binding switches family cleanly, ticket reuse / expiry / wrong principal / disabled principal fail.
# Synthetic IDs only; separate LOGINs; one-use tickets.
set -euo pipefail
app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap           -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001; FB=018f0000-0000-7000-8000-000000000002
SVC_P=018f0000-0000-7000-8000-000000002001
G_P=018f0000-0000-7000-8000-000000002002; G=018f0000-0000-7000-8000-000000001002
B_P=018f0000-0000-7000-8000-000000002006; B=018f0000-0000-7000-8000-000000001006
NEW_PERSON=018f0000-0000-7000-8000-00000000d001; NEW_MEMBER=018f0000-0000-7000-8000-00000000d002; NEW_P=018f0000-0000-7000-8000-00000000d003
M1=018f0000-0000-7000-8000-00000000d011; M2=018f0000-0000-7000-8000-00000000d012; M3=018f0000-0000-7000-8000-00000000d013; M4=018f0000-0000-7000-8000-00000000d014
ISS='https://idp.synthetic.invalid'
NONCE=018f0000-0000-7000-8000-00000000d099
check() { [ "$2" = "$3" ] && echo "PASS $1=$2" || { echo "FAIL $1 got=[$2] expected=[$3]"; exit 1; }; }
val()   { grep -m1 "^$1=" <<<"$2" | cut -d= -f2; }
ticket() { # principal actor(NULL) family(NULL) channel [interval] [nonce]
  local a=NULL f=NULL; [ "$2" != NULL ] && a="'$2'"; [ "$3" != NULL ] && f="'$3'"
  binder_psql -v ON_ERROR_STOP=1 -Atqc "SELECT auth.issue_context_ticket('$1',$a,$f,'$4',clock_timestamp()+interval '${5:-45 seconds}','${6:-$(cat /proc/sys/kernel/random/uuid)}','$1')"
}
session() { # principal actor family channel ; SQL on stdin
  local t; t="$(ticket "$1" "$2" "$3" "$4")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$1"; cat; printf "SELECT auth.clear_context();\n"; } \
    | app_psql -v ON_ERROR_STOP=1 -At -f - 2>&1 | grep -E '^[A-Z][A-Z0-9_]*=|ERROR' || true
}

echo "=== external identity mapping"
out="$(session $SVC_P NULL $FA INTERNAL <<SQL
SELECT 'MAP_GUARDIAN='||auth.register_external_identity('$M1','$ISS','synthetic-guardian-a','$G_P');
SELECT 'MAP_DUP='||auth.register_external_identity('$M2','$ISS','synthetic-guardian-a','$G_P');
SELECT 'MAP_SERVICE='||auth.register_external_identity('$M3','$ISS','synthetic-service','$SVC_P');
SELECT 'PERSON='||core.create_person('$NEW_PERSON','Synthetic V18 Member','$FA','$NEW_MEMBER','MEMBER');
SELECT 'PRINCIPAL='||auth.create_login_principal('$NEW_P','$NEW_PERSON','FAMILY');
SELECT 'MAP_NEW='||auth.register_external_identity('$M4','$ISS','synthetic-member','$NEW_P');
SQL
)"
check MAP_GUARDIAN "$(val MAP_GUARDIAN "$out")" true
check MAP_DUP "$(val MAP_DUP "$out")" false
check MAP_SERVICE "$(val MAP_SERVICE "$out")" false
check PERSON "$(val PERSON "$out")" true
check PRINCIPAL "$(val PRINCIPAL "$out")" true
check MAP_NEW "$(val MAP_NEW "$out")" true
check MAP_DUP_REASON "$(bootstrap_psql -Atqc "SELECT reason_code FROM audit.access_events WHERE resource_id='$M2' ORDER BY event_id DESC LIMIT 1")" ALREADY_ACTIVE
out="$(session $G_P $G $FA FAMILY <<SQL
SELECT 'MAP_BY_FAMILY='||auth.register_external_identity('018f0000-0000-7000-8000-00000000d015','$ISS','synthetic-self','$G_P');
SQL
)"
check MAP_BY_FAMILY "$(val MAP_BY_FAMILY "$out")" false
check RESOLVE_KNOWN "$(binder_psql -Atqc "SELECT coalesce(auth.resolve_external_identity('$ISS','synthetic-guardian-a')::text,'NULL')")" "$G_P"
check RESOLVE_UNKNOWN "$(binder_psql -Atqc "SELECT coalesce(auth.resolve_external_identity('$ISS','nobody')::text,'NULL')")" NULL
check RESOLVE_OTHER_ISSUER "$(binder_psql -Atqc "SELECT coalesce(auth.resolve_external_identity('https://other.invalid','synthetic-guardian-a')::text,'NULL')")" NULL
grep -q 'permission denied' <<<"$(app_psql -Atqc "SELECT auth.resolve_external_identity('$ISS','synthetic-guardian-a')" 2>&1)" && echo "PASS app cannot resolve identities" || { echo "FAIL app resolve"; exit 1; }
grep -q 'permission denied' <<<"$(binder_psql -Atqc "SELECT count(*) FROM auth.external_identities" 2>&1)" && echo "PASS binder cannot read the mapping table" || { echo "FAIL binder table read"; exit 1; }
out="$(session $SVC_P NULL $FA INTERNAL <<SQL
SELECT 'UNMAP_GUARDIAN='||auth.disable_external_identity('$M1');
SELECT 'DISABLE_NEW_PRINCIPAL='||auth.disable_login_principal('$NEW_P');
SQL
)"
check UNMAP_GUARDIAN "$(val UNMAP_GUARDIAN "$out")" true
check DISABLE_NEW_PRINCIPAL "$(val DISABLE_NEW_PRINCIPAL "$out")" true
check RESOLVE_AFTER_UNMAP "$(binder_psql -Atqc "SELECT coalesce(auth.resolve_external_identity('$ISS','synthetic-guardian-a')::text,'NULL')")" NULL
check RESOLVE_DISABLED_PRINCIPAL "$(binder_psql -Atqc "SELECT coalesce(auth.resolve_external_identity('$ISS','synthetic-member')::text,'NULL')")" NULL

echo "=== request number reaches the audit row"
t="$(ticket $G_P $G $FA FAMILY '45 seconds' $NONCE)"
printf "SELECT auth.redeem_context_ticket('%s','%s');\nSELECT core.create_family('018f0000-0000-7000-8000-00000000d098','Forbidden');\nSELECT auth.clear_context();\n" "$t" "$G_P" | app_psql -v ON_ERROR_STOP=1 -At -f - >/dev/null
check AUDIT_NONCE "$(bootstrap_psql -Atqc "SELECT request_nonce FROM audit.access_events WHERE resource_id='018f0000-0000-7000-8000-00000000d098' ORDER BY event_id DESC LIMIT 1")" "$NONCE"

echo "=== pool conformance on one backend"
tg="$(ticket $G_P $G $FA FAMILY)"; tb="$(ticket $B_P $B $FB FAMILY)"
out="$(app_psql -v ON_ERROR_STOP=1 -At <<SQL
SELECT 'PID_1='||pg_backend_pid();
SELECT auth.redeem_context_ticket('$tg','$G_P');
SELECT 'A_PEOPLE='||count(*) FROM core.people;
SELECT 'A_FAMILIES='||string_agg(family_id::text,',') FROM core.families;
SELECT auth.clear_context();
SELECT 'CLEARED_PEOPLE='||count(*) FROM core.people;
SELECT 'CLEARED_FAMILIES='||count(*) FROM core.families;
SELECT 'CLEARED_WRITE='||education.create_application('018f0000-0000-7000-8000-00000000d031','$FA','018f0000-0000-7000-8000-000000001003','X','Y','2031');
SELECT auth.redeem_context_ticket('$tb','$B_P');
SELECT 'B_FAMILIES='||string_agg(family_id::text,',') FROM core.families;
SELECT 'B_SEES_A_PEOPLE='||count(*) FROM core.people WHERE person_id='$G';
SELECT auth.clear_context();
SELECT 'PID_2='||pg_backend_pid();
SQL
)"
[ "$(val PID_1 "$out")" = "$(val PID_2 "$out")" ] && echo "PASS same backend reused (pid $(val PID_1 "$out"))" || { echo "FAIL backend changed"; exit 1; }
[ "$(val A_PEOPLE "$out")" -gt 0 ] && echo "PASS bound family A sees its people ($(val A_PEOPLE "$out"))" || { echo "FAIL A_PEOPLE"; exit 1; }
check A_FAMILIES "$(val A_FAMILIES "$out")" "$FA"
check CLEARED_PEOPLE "$(val CLEARED_PEOPLE "$out")" 0
check CLEARED_FAMILIES "$(val CLEARED_FAMILIES "$out")" 0
check CLEARED_WRITE "$(val CLEARED_WRITE "$out")" false
check B_FAMILIES "$(val B_FAMILIES "$out")" "$FB"
check B_SEES_A_PEOPLE "$(val B_SEES_A_PEOPLE "$out")" 0

t="$(ticket $G_P $G $FA FAMILY)"
reuse="$(printf "SELECT auth.redeem_context_ticket('%s','%s');\nSELECT auth.clear_context();\nSELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$G_P" "$t" "$G_P" | app_psql -v ON_ERROR_STOP=1 -At -f - 2>&1 || true)"
grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED' <<<"$reuse" && echo "PASS ticket reuse refused" || { echo "FAIL reuse: $reuse"; exit 1; }
t="$(ticket $G_P $G $FA FAMILY '1 second')"; sleep 2
exp="$(app_psql -v ON_ERROR_STOP=1 -Atc "SELECT auth.redeem_context_ticket('$t','$G_P')" 2>&1 || true)"
grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED' <<<"$exp" && echo "PASS expired ticket refused" || { echo "FAIL expired: $exp"; exit 1; }
t="$(ticket $G_P $G $FA FAMILY)"
wrong="$(app_psql -v ON_ERROR_STOP=1 -Atc "SELECT auth.redeem_context_ticket('$t','$B_P')" 2>&1 || true)"
grep -q 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED' <<<"$wrong" && echo "PASS ticket redeemed for another principal refused" || { echo "FAIL wrong principal: $wrong"; exit 1; }
issue_disabled="$(binder_psql -v ON_ERROR_STOP=1 -Atqc "SELECT auth.issue_context_ticket('$NEW_P','$NEW_PERSON','$FA','FAMILY',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$NEW_P')" 2>&1 || true)"
grep -q 'CONTEXT_PRINCIPAL_INVALID' <<<"$issue_disabled" && echo "PASS ticket for disabled principal refused" || { echo "FAIL disabled issue: $issue_disabled"; exit 1; }

echo "=== transaction-pooling hazard (expected behaviour, documented)"
t="$(ticket $G_P $G $FA FAMILY)"
hz="$(app_psql -v ON_ERROR_STOP=1 -At <<SQL
SELECT auth.redeem_context_ticket('$t','$G_P');
-- a second client handed this backend WITHOUT clear_context inherits the context:
SELECT 'INHERITED_FAMILY='||coalesce(auth.current_family_id()::text,'NULL');
SELECT auth.clear_context();
SELECT 'AFTER_CLEAR_FAMILY='||coalesce(auth.current_family_id()::text,'NULL');
SQL
)"
check INHERITED_FAMILY "$(val INHERITED_FAMILY "$hz")" "$FA"
check AFTER_CLEAR_FAMILY "$(val AFTER_CLEAR_FAMILY "$hz")" NULL
echo "NOTE context is bound to the backend: a pooler that hands one backend to several clients per transaction (for example PgBouncer transaction mode) would leak it; FD-6 rule 6 forbids such pooling and requires clear_context (or discarding the connection) before reuse"
echo "PASS V1.8 external identity, request trace and pool conformance"
