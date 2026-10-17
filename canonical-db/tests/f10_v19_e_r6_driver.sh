#!/usr/bin/env bash
# V1.9-R1 P1: runs tests/f10_v19_e_r6_repro.sh in one disposable PG container (network none, no host ports,
# synthetic data, removed at exit). Usage: tests/f10_v19_e_r6_driver.sh <16|17> [evidence-file]
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="${1:-}"; [ "$V" = 16 ] || [ "$V" = 17 ] || { echo "usage: $0 <16|17> [evidence-file]" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
EVIDENCE="${2:-}"
if [ -n "$EVIDENCE" ]; then exec > >(tee "$EVIDENCE") 2>&1; fi
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' \
              || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SUFFIX="$(date +%s)$RANDOM"; C="phoenix-canonical-v19r1-pg$V-$SUFFIX"
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }
mkdir -p "$ROOT/runtime"; chmod 700 "$ROOT/runtime" 2>/dev/null || true
SENV="$ROOT/runtime/v19r1-pg$V-$SUFFIX.env"
cleanup() { docker rm -f -v "$C" >/dev/null 2>&1; rm -f "$SENV"; }
trap cleanup EXIT
umask 077
printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$SENV"
expected="$(ls "$ROOT"/migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql | wc -l)"
echo "TASK=V1.9-R1 P1 E-R6 reproduction VERSION=$V IMAGE=$IMG MIGRATIONS=$expected HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) $(date '+%F %T %z')"
echo 'BOUNDARY: one disposable container, network none, no host ports, synthetic data only'
docker run -d --name "$C" --network none --env-file "$(winpath "$SENV")" "$IMG" >/dev/null || { echo "FAIL docker run"; exit 1; }
for _ in $(seq 1 60); do docker exec "$C" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && break; sleep 1; done
sleep 3
docker exec "$C" mkdir -p /opt/migrations /opt/tests
docker cp "$ROOT/migrations/canonical/." "$C:/opt/migrations" || { echo "FAIL copy migrations"; exit 1; }
docker cp "$ROOT/tests/." "$C:/opt/tests" || { echo "FAIL copy tests"; exit 1; }
docker exec -e F10_EXPECTED_MIGRATION_COUNT="$expected" "$C" bash /opt/tests/f10_ephemeral_init.sh > /dev/null || { echo "FAIL migration install"; exit 1; }
echo "PASS migrations installed: $expected"
if [ -n "${E_R6_CANDIDATE:-}" ]; then
  docker cp "$ROOT/$E_R6_CANDIDATE" "$C:/tmp/e_r6_candidate.sql" || { echo "FAIL copy candidate"; exit 1; }
  docker exec "$C" bash -c 'PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /tmp/e_r6_candidate.sql' > /dev/null || { echo "FAIL candidate apply"; exit 1; }
  echo "CANDIDATE APPLIED (not a migration; disposable container only): $E_R6_CANDIDATE"
fi
docker exec "$C" bash /opt/tests/f10_v19_e_r6_repro.sh
rc=$?
if [ "$rc" = 0 ]; then echo "RESULT no E-R6 finding"; else echo "RESULT FINDINGS PRESENT: the FINDING lines above are the E-R6 defect (open until a 0018 fix is approved and applied)"; fi
exit 0
