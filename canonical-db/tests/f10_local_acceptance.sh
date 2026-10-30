#!/usr/bin/env bash
# F10 full synthetic acceptance, bash edition (same steps as tests/f10_local_acceptance.ps1, for hosts
# without pwsh). Disposable containers only: --network none, no published ports, synthetic credentials
# in the git-ignored runtime/ directory, everything removed at exit.
# Usage: tests/f10_local_acceptance.sh <16|17> [evidence-file]
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="${1:-}"; [ "$V" = 16 ] || [ "$V" = 17 ] || { echo "usage: $0 <16|17> [evidence-file]" >&2; exit 2; }
# Under git-bash, docker and git are native Windows binaries: use the D:/... form of the path.
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
EVIDENCE="${2:-}"
if [ -n "$EVIDENCE" ]; then exec > >(tee "$EVIDENCE") 2>&1; fi
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' \
              || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SUFFIX="$(date +%s)$RANDOM"
SRC="phoenix-canonical-f10sh-src-pg$V-$SUFFIX"; RST="phoenix-canonical-f10sh-rst-pg$V-$SUFFIX"; VOL="phoenix_canonical_f10sh_pg${V}_$SUFFIX"
mkdir -p "$ROOT/runtime"; chmod 700 "$ROOT/runtime" 2>/dev/null || true
SENV="$ROOT/runtime/f10sh-src-pg$V-$SUFFIX.env"; RENV="$ROOT/runtime/f10sh-rst-pg$V-$SUFFIX.env"
AUDLOG="$ROOT/runtime/f10sh-audit-log-pg$V-$SUFFIX.txt"; AUDIDS="$ROOT/runtime/f10sh-audit-ids-pg$V-$SUFFIX.txt"
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }
cleanup() { docker rm -f -v "$SRC" "$RST" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; rm -f "$SENV" "$RENV" "$AUDLOG" "$AUDIDS" "$AUDLOG.ids"; }
trap cleanup EXIT
mkenv() { umask 077; printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$1"; }
wait_db() { for _ in $(seq 1 60); do docker exec "$1" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && return 0; sleep 1; done; echo "FAIL database not ready: $1"; exit 1; }
run() { echo "COMMAND: $1"; shift; docker "$@" 2>&1; local rc=$?; [ $rc -eq 0 ] || { echo "FAIL rc=$rc"; exit $rc; }; }
refuse() { echo "COMMAND: $1 (expected refusal)"; shift; local out rc; out="$(docker "$@" 2>&1)"; rc=$?; printf '%s\n' "$out" | tail -2; [ $rc -ne 0 ] && echo "PASS refused rc=$rc" || { echo "FAIL unexpectedly accepted"; exit 1; }; }
psqlf() { local name="$1" file="$2" out rc; out="$(docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$name" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f "/opt/tests/$file" 2>&1)"; rc=$?; printf '%s\n' "$out" | grep -E 'PASS|ERROR'; [ $rc -eq 0 ] && echo "PASS psql $file" || { echo "FAIL psql $file rc=$rc"; exit 1; }; }

mkenv "$SENV"; mkenv "$RENV"
expected="$(ls "$ROOT"/migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql | wc -l)"
last="$(ls "$ROOT"/migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql | tail -1)"; last_name="$(basename "$last")"
next="$(printf '%04d' $((10#${last_name:0:4} + 1)))"
echo "TASK=F10 bash acceptance VERSION=$V IMAGE=$IMG MIGRATIONS=$expected HEAD=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null) DIRTY=$(git -C "$ROOT" status --short 2>/dev/null | wc -l) $(date '+%F %T %z')"
echo "MIGRATION_SHA256:"; for m in "$ROOT"/migrations/canonical/*.sql; do printf '  %s %s\n' "$(sha256sum "$m" | cut -d' ' -f1)" "$(basename "$m")"; done
echo 'BOUNDARY: one-off containers, network none, no host ports, no existing Compose volumes'
run "volume create" volume create "$VOL"
run "docker run source --network none" run -d --name "$SRC" --network none --env-file "$(winpath "$SENV")" --mount "type=volume,source=$VOL,target=/f10backup" "$IMG"
wait_db "$SRC"; sleep 3
docker exec "$SRC" mkdir -p /opt/migrations /opt/tests
run "copy migrations" cp "$ROOT/migrations/canonical/." "$SRC:/opt/migrations"
run "copy tests" cp "$ROOT/tests/." "$SRC:/opt/tests"

echo "=== migration inventory: 0001-0010 first, then the rest; repeat; guards"
docker exec "$SRC" bash -c 'mkdir -p /tmp/staged && for f in /opt/migrations/*.sql; do n=$(basename "$f"); [ "${n:0:4}" -gt 10 ] && mv "$f" /tmp/staged/; done; true'
run "init expected=10" exec -e F10_EXPECTED_MIGRATION_COUNT=10 "$SRC" bash /opt/tests/f10_ephemeral_init.sh
docker exec "$SRC" bash -c 'mv /tmp/staged/*.sql /opt/migrations/'
run "init expected=$expected" exec -e F10_EXPECTED_MIGRATION_COUNT="$expected" "$SRC" bash /opt/tests/f10_ephemeral_init.sh
run "init repeat" exec -e F10_EXPECTED_MIGRATION_COUNT="$expected" "$SRC" bash /opt/tests/f10_ephemeral_init.sh
refuse "extra empty ${next} file" exec "$SRC" bash -c "touch /opt/migrations/${next}_extra_probe.sql; bash /opt/tests/f10_ephemeral_init.sh"
docker exec "$SRC" rm "/opt/migrations/${next}_extra_probe.sql"
refuse "latest migration hidden" exec "$SRC" bash -c "mv /opt/migrations/$last_name /tmp/; bash /opt/tests/f10_ephemeral_init.sh"
docker exec "$SRC" mv "/tmp/$last_name" /opt/migrations/
refuse "unnumbered .sql file" exec "$SRC" bash -c 'touch /opt/migrations/zz_unnumbered.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" rm /opt/migrations/zz_unnumbered.sql

# V1.9-R1 E-R6: optional candidate fix applied after migrations and before the suites (default off, not a migration).
if [ -n "${F10_CANDIDATE_SQL:-}" ]; then
  docker cp "$ROOT/$F10_CANDIDATE_SQL" "$SRC:/tmp/f10_candidate.sql" || { echo "FAIL copy candidate"; exit 1; }
  docker exec "$SRC" bash -c 'PGPASSFILE=/tmp/f10-bootstrap.pgpass psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /tmp/f10_candidate.sql' >/dev/null || { echo "FAIL candidate apply"; exit 1; }
  echo "CANDIDATE APPLIED (not a migration): $F10_CANDIDATE_SQL"
fi
echo "=== suites"
for s in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql; do psqlf "$SRC" "$s"; done
# V1.9 P5 PoC: optional move of table/function ownership to a NOLOGIN owner role (default off).
if [ "${F10_OWNER_TRANSFER:-0}" = 1 ]; then
  psqlf "$SRC" owner_transfer.sql
  psqlf "$SRC" owner_transfer_check.sql
fi
run "API seed" exec "$SRC" bash /opt/tests/f10_ephemeral_seed.sh
run "F10 regression" exec "$SRC" bash /opt/tests/f10_ephemeral_regression.sh
run "C1-C10 probes" exec "$SRC" bash /opt/tests/claude_f10_reaudit_probes.sh
run "R-20 channel/kind" exec "$SRC" bash /opt/tests/f10_v15_channel_kind.sh
run "G1-G5" exec "$SRC" bash /opt/tests/f10_v15_gap_regression.sh
run "V1.6 T1-T4" exec "$SRC" bash /opt/tests/f10_v16_contract_gaps.sh
psqlf "$SRC" f10_v16_document_trigger.sql
run "V1.7 assignment scope" exec "$SRC" bash /opt/tests/f10_v17_assignment_scope.sh
run "V1.8 external identity, request trace, pool conformance" exec "$SRC" bash /opt/tests/f10_v18_identity_pool.sh
run "V1.9 E-R6 closed-case advisor boundary" exec "$SRC" bash /opt/tests/f10_v19_e_r6_repro.sh
run "0018 D-2 legacy binder entry revocation" exec "$SRC" bash /opt/tests/f10_v20_0018_acl.sh
run "0019 Education master and records" exec "$SRC" bash /opt/tests/f10_v21_0019_education.sh
run "0021 Operations entitlement reference" exec "$SRC" bash /opt/tests/f10_v22_0021_operations_entitlement.sh
run "0022 Learning Core" exec "$SRC" bash /opt/tests/f10_v23_0022_learning.sh
run "0023 application family context resolver" exec "$SRC" bash /opt/tests/f10_v25_0023_application_family_context.sh
run "0024 managed family mapping lifecycle" exec "$SRC" bash /opt/tests/f10_v28_0024_family_mapping_management.sh

echo "=== D-9 reconciliation (server log vs persisted audit rows)"
docker logs "$SRC" 2>&1 | grep 'PHOENIX_AUDIT' > "$AUDLOG"
grep -qE 'Synthetic Renamed|Forbidden Cross Family' "$AUDLOG" && { echo "FAIL display name leaked into PHOENIX_AUDIT"; exit 1; }
echo "PASS T1 display names absent from PHOENIX_AUDIT log"
docker exec -e PGPASSFILE=/tmp/f10-backup.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -c 'SELECT attempt_id FROM audit.access_events WHERE attempt_id IS NOT NULL ORDER BY event_id' | sort -u > "$AUDIDS"
grep -oE 'attempt_id=[0-9a-f-]{36}' "$AUDLOG" | cut -d= -f2 | sort -u > "$AUDLOG.ids"
total="$(wc -l < "$AUDLOG.ids")"; logonly="$(comm -23 "$AUDLOG.ids" "$AUDIDS" | wc -l)"
echo "LOG_ATTEMPTS=$total PERSISTED_MATCHES=$((total-logonly)) LOG_ONLY_ATTEMPTS=$logonly"
comm -23 "$AUDLOG.ids" "$AUDIDS" | while read -r id; do grep "attempt_id=$id" "$AUDLOG" | sed -E 's/.*(PHOENIX_AUDIT .*) principal_id.*/ROLLED_BACK_ATTEMPT \1/'; done
comm -23 "$AUDLOG.ids" "$AUDIDS" | while read -r id; do grep "attempt_id=$id" "$AUDLOG"; done | grep -q 'resource_id=018f0000-0000-7000-8000-000000009902 decision=DENY' \
  && echo "PASS D9 rolled-back denial present only in server log" || { echo "FAIL D9 reconciliation"; exit 1; }
grep -q 'request_nonce=018f0000-0000-7000-8000-00000000d099$' "$AUDLOG" \
  && echo "PASS FD-6 request number present in the PHOENIX_AUDIT server log line" || { echo "FAIL request number missing from server log"; exit 1; }
psqlf "$SRC" f10_d6_immutability_regression.sql
psqlf "$SRC" f10_v15_schema_installer.sql

echo "=== socket / hba / drift / atomicity"
docker exec "$SRC" psql -X -w -U phoenix_bootstrap -d phoenix_canonical_dev -Atc 'SELECT 1' >/dev/null 2>&1 && { echo "FAIL unauthenticated socket accepted"; exit 1; }
echo "PASS socket password required"
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT type||'|'||auth_method FROM pg_hba_file_rules WHERE type IN ('local','host') ORDER BY line_number"
refuse "0009 drift" exec "$SRC" bash -c 'printf "\n-- synthetic drift probe\n" >> /opt/migrations/0009_application_write_api.sql; bash /opt/tests/f10_ephemeral_init.sh'
run "restore pristine 0009" cp "$ROOT/migrations/canonical/0009_application_write_api.sql" "$SRC:/opt/migrations/0009_application_write_api.sql"
refuse "forced migration failure" exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/9000_atomicity_probe.sql
atomic="$(docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT (to_regnamespace('acceptance_atomicity_probe') IS NOT NULL)::text||':'||count(*) FROM canonical_migrations.applied")"
[ "$atomic" = "false:$expected" ] && echo "PASS atomic rollback left no schema; ledger=$expected" || { echo "FAIL atomicity $atomic"; exit 1; }

echo "=== backup LOGIN dump and fresh-cluster restore"
run "backup role dump" exec "$SRC" bash -c 'set -euo pipefail; umask 077; export PGPASSFILE=/tmp/f10-backup.pgpass; pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -Fc > /f10backup/source.dump; sha256sum /f10backup/source.dump | cut -d" " -f1 > /f10backup/source.dump.sha256; stat -c "DUMP_MODE=%a DUMP_SIZE=%s" /f10backup/source.dump; echo "DUMP_SHA=$(cat /f10backup/source.dump.sha256)"; echo "PG_RESTORE_ENTRIES=$(pg_restore -l /f10backup/source.dump | grep -c "^[0-9]*;")"'
run "docker run restore --network none" run -d --name "$RST" --network none --env-file "$(winpath "$RENV")" --mount "type=volume,source=$VOL,target=/f10backup,readonly" "$IMG"
wait_db "$RST"; sleep 3
docker exec "$RST" mkdir -p /opt/tests
run "copy tests to restore" cp "$ROOT/tests/." "$RST:/opt/tests"
run "fresh-cluster restore" exec -e F10_OWNER_TRANSFER="${F10_OWNER_TRANSFER:-0}" "$RST" bash /opt/tests/f10_ephemeral_restore.sh
docker inspect "$SRC" --format 'SRC NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
docker inspect "$RST" --format 'RST NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "PASS PostgreSQL $V F10 full synthetic acceptance (bash)"
echo "END $(date '+%F %T %z')"
