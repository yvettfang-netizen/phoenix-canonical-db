#!/usr/bin/env bash
# Upgrade-path acceptance: a database at 0006 (the state of the paused Tencent runtime) with synthetic
# data is upgraded to the latest migration. A blocking pre-0012 row (SERVICE principal with a natural
# person) must be reported by the preflight, make the upgrade stop atomically at 0012 with data intact,
# and, once removed, let the upgrade finish. Disposable container, --network none, no ports.
# Usage: tests/upgrade_path_acceptance.sh <16|17> [evidence-file]
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="${1:-}"; [ "$V" = 16 ] || [ "$V" = 17 ] || { echo "usage: $0 <16|17> [evidence-file]" >&2; exit 2; }
# Under git-bash, docker and git are native Windows binaries: use the D:/... form of the path.
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
[ -n "${2:-}" ] && exec > >(tee "$2") 2>&1
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' \
              || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SUFFIX="$(date +%s)$RANDOM"; SRC="phoenix-canonical-upgrade-pg$V-$SUFFIX"
mkdir -p "$ROOT/runtime"; SENV="$ROOT/runtime/upgrade-pg$V-$SUFFIX.env"
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }
cleanup() { docker rm -f -v "$SRC" >/dev/null 2>&1; rm -f "$SENV"; }
trap cleanup EXIT
fail() { echo "FAIL $*"; exit 1; }
q() { docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
umask 077
printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$SENV"
latest="$(ls "$ROOT"/migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql | wc -l)"
echo "TASK=upgrade-path VERSION=$V IMAGE=$IMG FROM=0006 TO=$latest HEAD=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null) $(date '+%F %T %z')"
docker run -d --name "$SRC" --network none --env-file "$(winpath "$SENV")" "$IMG" >/dev/null || fail "docker run"
for _ in $(seq 1 60); do docker exec "$SRC" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && break; sleep 1; done; sleep 3
docker exec "$SRC" mkdir -p /opt/migrations /opt/tests /opt/deploy /tmp/staged
docker cp "$ROOT/migrations/canonical/." "$SRC:/opt/migrations" >/dev/null || fail "copy migrations"
docker cp "$ROOT/tests/." "$SRC:/opt/tests" >/dev/null || fail "copy tests"
docker cp "$ROOT/deploy/tencent/preflight_upgrade.sql" "$SRC:/opt/deploy/preflight_upgrade.sql" >/dev/null || fail "copy preflight"

counts() { q -c "SELECT string_agg(t||'='||n, ' ' ORDER BY t) FROM (VALUES
  ('people',(SELECT count(*) FROM core.people)),('families',(SELECT count(*) FROM core.families)),
  ('memberships',(SELECT count(*) FROM core.family_memberships)),('students',(SELECT count(*) FROM core.student_profiles)),
  ('principals',(SELECT count(*) FROM auth.principals)),('guardians',(SELECT count(*) FROM core.guardian_authorities)),
  ('consents',(SELECT count(*) FROM consent.grants)),('applications',(SELECT count(*) FROM education.applications)),
  ('identity_cases',(SELECT count(*) FROM identity.cases)),('cases',(SELECT count(*) FROM casework.cases)),
  ('assignments',(SELECT count(*) FROM casework.advisor_assignments)),('documents',(SELECT count(*) FROM docs.documents)),
  ('versions',(SELECT count(*) FROM docs.document_versions)),('manifests',(SELECT count(*) FROM docs.submission_manifests)),
  ('items',(SELECT count(*) FROM docs.submission_items))) v(t,n)"; }

echo "=== 1. install 0001-0006 only"
docker exec "$SRC" bash -c 'for f in /opt/migrations/*.sql; do n=$(basename "$f"); [ "${n:0:4}" -gt 6 ] && mv "$f" /tmp/staged/; done; true'
docker exec -e F10_EXPECTED_MIGRATION_COUNT=6 "$SRC" bash /opt/tests/f10_ephemeral_init.sh | grep -E 'APPLIED|PASS|FAIL' || fail "install 0001-0006"
echo "=== 2. synthetic data at 0006 + one blocking row (SERVICE principal with a natural person)"
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/upgrade_seed_0006.sql || fail "seed"
q -c "INSERT INTO core.people(person_id,display_name) VALUES ('018f0000-0000-7000-8000-0000000e0004','Upgrade Legacy Service');
      INSERT INTO auth.principals(principal_id,person_id,principal_kind,status) VALUES ('018f0000-0000-7000-8000-0000000e0024','018f0000-0000-7000-8000-0000000e0004','SERVICE','ACTIVE');" >/dev/null || fail "blocking row"
before="$(counts)"; echo "COUNTS_0006 $before"
echo "=== 3. preflight must report the blocking row"
pre="$(docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -At -F' | ' -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -f /opt/deploy/preflight_upgrade.sql 2>&1)"; printf '%s\n' "$pre"
grep -q '^service_principal_with_person | t | rows=1' <<<"$pre" || fail "preflight did not report the blocking row"
[ "$(grep -c ' | t | ' <<<"$pre")" = 1 ] || fail "unexpected blocking rows"
echo "PASS preflight reported exactly one blocking condition"
echo "=== 4. upgrade must stop atomically at 0012"
docker exec "$SRC" bash -c 'mv /tmp/staged/*.sql /opt/migrations/'
out="$(docker exec -e F10_EXPECTED_MIGRATION_COUNT="$latest" "$SRC" bash /opt/tests/f10_ephemeral_init.sh 2>&1)"; rc=$?
printf '%s\n' "$out" | grep -E 'APPLIED|SKIP|ERROR|FAIL|PASS' | sed -E 's/ [0-9a-f]{64}$//'
[ $rc -ne 0 ] || fail "upgrade unexpectedly succeeded with a blocking row"
ledger="$(q -c 'SELECT count(*)||'"'"':'"'"'||max(migration_name) FROM canonical_migrations.applied')"; echo "LEDGER_AFTER_FAILURE $ledger"
[ "${ledger%%:*}" = 11 ] || fail "expected ledger 11 after the 0012 failure"
[ "$(q -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='auth' AND table_name='principals' AND column_name='service_label'")" = 0 ] || fail "0012 partially applied"
after_fail="$(counts)"; [ "$after_fail" = "$before" ] || fail "data changed by the failed upgrade: $after_fail"
echo "PASS upgrade stopped at 0012, 0007-0011 applied, 0012 left no trace, data unchanged"
echo "=== 5. remove the blocking row (test-only remediation), preflight clean, upgrade completes"
q -c "DELETE FROM auth.principals WHERE principal_id='018f0000-0000-7000-8000-0000000e0024'; DELETE FROM core.people WHERE person_id='018f0000-0000-7000-8000-0000000e0004';" >/dev/null || fail "remediation"
expected_after="$(counts)"
pre="$(docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -At -F' | ' -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -f /opt/deploy/preflight_upgrade.sql 2>&1)"; printf '%s\n' "$pre"
grep -q ' | t | ' <<<"$pre" && fail "preflight still blocking"
docker exec -e F10_EXPECTED_MIGRATION_COUNT="$latest" "$SRC" bash /opt/tests/f10_ephemeral_init.sh 2>&1 | grep -E 'APPLIED|SKIP|PASS|FAIL|ledger=|tables=|policies=' | sed -E 's/ [0-9a-f]{64}$//'
[ "${PIPESTATUS[0]}" = 0 ] || fail "upgrade after remediation"
final="$(counts)"; echo "COUNTS_FINAL $final"
[ "$final" = "$expected_after" ] || fail "row counts changed by the upgrade"
echo "=== 6. upgraded data is consistent with the new rules"
q -c "SELECT 'assignment_lifecycle='||string_agg(lifecycle_status,',') FROM casework.advisor_assignments;
      SELECT 'guardian_lifecycle='||string_agg(lifecycle_status,',') FROM core.guardian_authorities;
      SELECT 'principal_kind_person_ok='||bool_and((principal_kind='SERVICE')=(person_id IS NULL)) FROM auth.principals;
      SELECT 'manifest_confirmation_ok='||bool_and((confirmed_by IS NULL)=(confirmed_at IS NULL)) FROM docs.submission_manifests;
      SELECT 'case_resource_subject_ok='||bool_and(x.student_person_id=c.subject_person_id) FROM casework.cases c JOIN education.applications x ON x.application_id=c.resource_id;
      SELECT 'audit_attempt_column='||count(*) FROM information_schema.columns WHERE table_schema='audit' AND table_name='access_events' AND column_name='attempt_id';"
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/f10_catalog_regression.sql 2>&1 | grep -E 'PASS|ERROR' || fail "catalog regression"
docker inspect "$SRC" --format 'NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "PASS upgrade path 0006 -> $(printf '%04d' "$latest") PostgreSQL $V"
