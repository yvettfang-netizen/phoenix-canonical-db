#!/usr/bin/env bash
# Claude independent probes for 0009 (runs inside the disposable container after f10 seed + regression).
set -uo pipefail
app_psql()       { PGPASSFILE=/tmp/f10-app.pgpass       psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10    -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql()    { PGPASSFILE=/tmp/f10-binder.pgpass    psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
bootstrap_psql() { PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap           -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001; FB=018f0000-0000-7000-8000-000000000002
SVC_P=018f0000-0000-7000-8000-000000002001; SVC=NULL
STU_P=018f0000-0000-7000-8000-000000002003; STU=018f0000-0000-7000-8000-000000001003
B_P=018f0000-0000-7000-8000-000000002006;   B=018f0000-0000-7000-8000-000000001006
PARTNER=018f0000-0000-7000-8000-000000001005
ticket() { local actor="'$2'::uuid"; [ "$2" = NULL ] && actor=NULL; binder_psql -Atqc "SELECT auth.issue_context_ticket('$1',$actor,'$3','$4',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')"; }
redeem() { printf "SELECT auth.redeem_context_ticket('%s'::uuid,'%s'::uuid);\n" "$1" "$2"; }

echo "C1 app LOGIN direct INSERT into core.people: $(app_psql -Atqc "INSERT INTO core.people(person_id,display_name) VALUES ('018f0000-0000-7000-8000-000000009901','X')" 2>&1 | grep -o 'ERROR:.*' | head -1)"

T="$(ticket $B_P $B $FB FAMILY)"
{ echo "BEGIN;"; redeem "$T" "$B_P"
  echo "SELECT 'C2 in-txn family-B create_application for family-A student returned='||education.create_application('018f0000-0000-7000-8000-000000009902','$FA','$STU','SYN U','SYN P','2027');"
  echo "ROLLBACK;"; } | app_psql -At -f - 2>&1 | grep -v '^$'
c2_rows="$(bootstrap_psql -Atqc "SELECT count(*) FROM audit.access_events WHERE resource_id='018f0000-0000-7000-8000-000000009902'")"
echo "C2 database rows after client ROLLBACK: $c2_rows; server LOG is asserted by f10_audit_reconcile.ps1"
test "$c2_rows" = 0 || exit 1
T="$(ticket $B_P $B $FB FAMILY)"
{ redeem "$T" "$B_P"; echo "SELECT education.create_application('018f0000-0000-7000-8000-000000009903','$FA','$STU','SYN U','SYN P','2027');"; } | app_psql -At -f - >/dev/null 2>&1
c2_control="$(bootstrap_psql -Atqc "SELECT count(*) FROM audit.access_events WHERE resource_id='018f0000-0000-7000-8000-000000009903' AND decision='DENY'")"
echo "C2b same attempt committed (control): DENY rows=$c2_control"
test "$c2_control" = 1 || exit 1

c3_family="$(bootstrap_psql -Atqc "SELECT count(*) FROM core.families WHERE family_id='018f0000-0000-7000-8000-000000000001'")"
c3_service="$(bootstrap_psql -Atqc "SELECT count(*) FROM auth.principals WHERE principal_kind='SERVICE' AND person_id IS NULL")"
c3_management="$(bootstrap_psql -Atqc "SELECT count(*) FROM auth.principals WHERE principal_id='$SVC_P' AND principal_kind='SERVICE' AND person_id IS NULL")"
echo "C3 unbound SERVICE family bootstrap exists: $c3_family"
echo "C3b SERVICE principal has no person: $c3_service"
test "$c3_family" = 1 && test "$c3_management" = 1 && test "$c3_service" -ge 1 || exit 1
echo 'PASS C2/C3 rollback-resistant log handoff and unbound personless SERVICE expectations'

T="$(ticket $STU_P $STU $FA FAMILY)"
student_probe="$({ redeem "$T" "$STU_P"
  echo "SELECT 'C4 student self-grants IDENTITY_SENSITIVE DOCUMENT_READ to partner returned='||consent.create_grant('018f0000-0000-7000-8000-000000009904','$FA','$PARTNER','$STU','DOCUMENT_READ','IDENTITY_SENSITIVE',clock_timestamp()+interval '30 days');"
  echo "SELECT 'C5 student creates own application='||education.create_application('018f0000-0000-7000-8000-000000009905','$FA','$STU','SYN U2','SYN P2','2027');"
  echo "SELECT 'C5 READY='||education.advance_application('018f0000-0000-7000-8000-000000009905','READY');"
  echo "SELECT 'C5 SUBMITTED='||education.advance_application('018f0000-0000-7000-8000-000000009905','SUBMITTED');"
  echo "SELECT 'C5 DECIDED (no external decision fact)='||education.advance_application('018f0000-0000-7000-8000-000000009905','DECIDED');"
  echo "SELECT auth.clear_context();"; } | app_psql -At -f - 2>&1 | grep -v -E '^$')"
printf '%s\n' "$student_probe"
grep -q 'C4 student self-grants IDENTITY_SENSITIVE DOCUMENT_READ to partner returned=false' <<<"$student_probe" || exit 1
grep -q 'C5 DECIDED (no external decision fact)=false' <<<"$student_probe" || exit 1
echo 'PASS C4/C5 unauthorized self grant and decision denied'
echo "C5b external decision facts recorded for that application: $(bootstrap_psql -Atqc "SELECT count(*) FROM education.external_facts WHERE application_id='018f0000-0000-7000-8000-000000009905'")"

T="$(ticket $SVC_P $SVC $FA INTERNAL)"
{ redeem "$T" "$SVC_P"
  echo "SELECT 'C6 service bound to family A creates person in family B returned='||core.create_person('018f0000-0000-7000-8000-000000009906','SYN X','$FB','018f0000-0000-7000-8000-000000009907','MEMBER');"
  echo "SELECT 'C7a service creates document='||docs.create_document('018f0000-0000-7000-8000-000000009908','$FA','$STU','GENERAL','SYN form',clock_timestamp()+interval '365 days');"
  echo "SELECT 'C7b non-mock storage key cos://... returned='||docs.append_document_version('018f0000-0000-7000-8000-000000009909','018f0000-0000-7000-8000-000000009908',1,repeat('a',64),'cos://bucket/real-object-01','10');"
  echo "SELECT 'C7c mock storage key returned='||docs.append_document_version('018f0000-0000-7000-8000-000000009910','018f0000-0000-7000-8000-000000009908',1,repeat('b',64),'mock/syn/obj-0001','10');"
  echo "SELECT 'C7d version 3 skipping 2 returned='||docs.append_document_version('018f0000-0000-7000-8000-000000009911','018f0000-0000-7000-8000-000000009908',3,repeat('c',64),'mock/syn/obj-0003','10');"
  echo "SELECT auth.clear_context();"; } | app_psql -At -f - 2>&1 | grep -v -E '^$'

c8="$(bootstrap_psql -Atqc "SELECT count(*) FILTER (WHERE confirmed_by=submitted_by)||' of '||count(*) FROM docs.submission_manifests WHERE status='SUBMITTED'")"
echo "C8 submitted manifests where confirmed_by = submitted_by: $c8"
test "${c8%% of *}" = 0 || exit 1
echo 'PASS C8 submitter differs from confirmer'
echo "C9 API coverage (functions app can execute that INSERT into casework/guardian/principal/channel tables): $(bootstrap_psql -Atqc "SELECT coalesce(string_agg(n.nspname||'.'||p.proname,','),'none') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE has_function_privilege('phoenix_canonical_app',p.oid,'EXECUTE') AND (p.prosrc ~* 'INSERT INTO (casework\.|core\.guardian_authorities|auth\.principals|integration\.channel_grants)')")"
echo "C10 app executable write functions: $(bootstrap_psql -Atqc "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') AND p.provolatile='v' AND has_function_privilege('phoenix_canonical_app',p.oid,'EXECUTE')")"
echo "END claude probes"
