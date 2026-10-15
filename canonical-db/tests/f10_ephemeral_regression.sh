#!/usr/bin/env bash
set -euo pipefail
umask 077

app_psql() {
  PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -h 127.0.0.1 \
    -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}
binder_psql() {
  PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 \
    -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}
bootstrap_psql() {
  PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 \
    -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"
}

run_session() {
  local label="$1" principal="$2" actor="$3" family="$4" channel="$5" file="$6" duration="${7:-45 seconds}"
  local ticket
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal','$actor','$family','$channel',clock_timestamp()+interval '$duration',gen_random_uuid(),'$principal')")"
  test "$ticket" != ''
  echo "SESSION $label binder_LOGIN=phoenix_canonical_binder_f10 app_LOGIN=phoenix_canonical_app_f10"
  {
    printf "SELECT auth.redeem_context_ticket('%s'::uuid,'%s'::uuid);\n" "$ticket" "$principal"
    cat "$file"
    printf '\nSELECT auth.clear_context();\n'
  } | app_psql -f -
  unset ticket
}

echo 'TEST separate LOGIN accounts; no SET ROLE; one-use binder ticket exchanged on app connection'
app_psql -f /opt/tests/f10_no_context_regression.sql

run_session SERVICE_A '018f0000-0000-7000-8000-000000002001' \
  '018f0000-0000-7000-8000-000000001001' '018f0000-0000-7000-8000-000000000001' INTERNAL \
  /opt/tests/f10_service_regression.sql
run_session FAMILY_A_CREATE '018f0000-0000-7000-8000-000000002002' \
  '018f0000-0000-7000-8000-000000001002' '018f0000-0000-7000-8000-000000000001' FAMILY \
  /opt/tests/f10_family_create_regression.sql
run_session ADVISOR_NO_CONSENT '018f0000-0000-7000-8000-000000002004' \
  '018f0000-0000-7000-8000-000000001004' '018f0000-0000-7000-8000-000000000001' ADVISOR \
  /opt/tests/f10_advisor_pre_regression.sql
run_session FAMILY_A_CONSENT '018f0000-0000-7000-8000-000000002002' \
  '018f0000-0000-7000-8000-000000001002' '018f0000-0000-7000-8000-000000000001' FAMILY \
  /opt/tests/f10_family_consent_regression.sql
run_session ADVISOR_WITH_CONSENT '018f0000-0000-7000-8000-000000002004' \
  '018f0000-0000-7000-8000-000000001004' '018f0000-0000-7000-8000-000000000001' ADVISOR \
  /opt/tests/f10_advisor_post_regression.sql
run_session FAMILY_A_FINISH '018f0000-0000-7000-8000-000000002002' \
  '018f0000-0000-7000-8000-000000001002' '018f0000-0000-7000-8000-000000000001' FAMILY \
  /opt/tests/f10_family_finish_regression.sql
run_session PARTNER_DENIED '018f0000-0000-7000-8000-000000002005' \
  '018f0000-0000-7000-8000-000000001005' '018f0000-0000-7000-8000-000000000001' PARTNER \
  /opt/tests/f10_partner_regression.sql
run_session CROSS_FAMILY '018f0000-0000-7000-8000-000000002006' \
  '018f0000-0000-7000-8000-000000001006' '018f0000-0000-7000-8000-000000000002' FAMILY \
  /opt/tests/f10_cross_family_regression.sql
run_session EXPIRED_CONTEXT '018f0000-0000-7000-8000-000000002001' \
  '018f0000-0000-7000-8000-000000001001' '018f0000-0000-7000-8000-000000000001' INTERNAL \
  /opt/tests/f10_expired_context_regression.sql '1 second'

bootstrap_psql -f /opt/tests/f10_guardian_evidence_regression.sql
bootstrap_psql -f /opt/tests/f10_catalog_regression.sql
bootstrap_psql -Atqc "SELECT 'audit_allow='||count(*) FROM audit.access_events WHERE decision='ALLOW'; SELECT 'audit_deny='||count(*) FROM audit.access_events WHERE decision='DENY'; SELECT 'ledger='||count(*) FROM canonical_migrations.applied;"
echo 'PASS F10 separated-login synthetic regression'
