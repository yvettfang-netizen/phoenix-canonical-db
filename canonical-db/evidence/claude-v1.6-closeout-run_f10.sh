#!/usr/bin/env bash
# Claude V1.6 closeout re-run: bash mirror of tests/f10_local_acceptance.ps1 (0001-0015; pwsh unavailable on
# this host) plus Claude probes. Disposable containers only (--network none, no ports); synthetic env files
# kept outside the repository and removed at exit. Usage: claude_v16_run_f10.sh <16|17>
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="$1"
ROOT="D:/CODEX/01_PHOENIX/01_NOVA/_worktrees/canonical-postgresql-phase1/canonical-db"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SRC="claude-v16-src-pg$V-$RANDOM"; RST="claude-v16-rst-pg$V-$RANDOM"; VOL="claude_v16_bak_pg${V}_$RANDOM"
SENV="$HERE/src$V.env"; RENV="$HERE/rst$V.env"; AUDLOG="$HERE/audit-log-pg$V.txt"; AUDIDS="$HERE/audit-ids-pg$V.txt"
cleanup() { docker rm -f "$SRC" "$RST" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; rm -f "$SENV" "$RENV"; }
trap cleanup EXIT
mkenv() { printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$1"; }
wait_db() { for i in $(seq 1 60); do docker exec "$1" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
run() { echo "COMMAND: $1"; shift; docker "$@" 2>&1; local rc=$?; [ $rc -eq 0 ] || { echo "FAILED rc=$rc"; exit $rc; }; }
expect_fail() { echo "COMMAND: $1 (expected refusal)"; shift; local out; out="$(docker "$@" 2>&1)"; local rc=$?; printf '%s\n' "$out" | tail -2; if [ $rc -ne 0 ]; then echo "PASS refused rc=$rc"; else echo "FAIL unexpectedly accepted"; exit 1; fi; }
psqlf() { docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f "/opt/tests/$1" 2>&1 | grep -E 'PASS|ERROR' ; local rc=${PIPESTATUS[0]}; [ $rc -eq 0 ] && echo "PASS psql $1" || { echo "FAIL psql $1 rc=$rc"; exit 1; }; }
mkenv "$SENV"; mkenv "$RENV"
echo "TASK=Claude-V1.6-closeout VERSION=$V IMAGE=$IMG HEAD=$(git -C "$ROOT" rev-parse --short HEAD) WORKTREE_DIRTY=$(git -C "$ROOT" status --short | wc -l) $(date '+%F %T %z')"
echo "MIGRATION_SHA256:"; for m in "$ROOT"/migrations/canonical/*.sql; do printf '  %s %s\n' "$(sha256sum "$m" | cut -c1-16)" "$(basename "$m")"; done
run "volume create" volume create "$VOL" >/dev/null
run "docker run source --network none" run -d --name "$SRC" --network none --env-file "$(cygpath -w "$SENV")" --mount "type=volume,source=$VOL,target=/f10backup" "$IMG" >/dev/null
wait_db "$SRC"; sleep 3
docker exec "$SRC" mkdir -p /opt/migrations /opt/tests /opt/claude
docker cp "$ROOT/migrations/canonical/." "$SRC:/opt/migrations" >/dev/null
docker cp "$ROOT/tests/." "$SRC:/opt/tests" >/dev/null
docker cp "$HERE/claude_v16_probes.sh" "$SRC:/opt/claude/claude_v16_probes.sh" >/dev/null

echo "=== migration inventory: 0001-0010 first, then 0011-0015, repeat, guards"
docker exec "$SRC" bash -c 'mv /opt/migrations/001[1-5]_*.sql /tmp/'
run "init expected=10" exec -e F10_EXPECTED_MIGRATION_COUNT=10 "$SRC" bash /opt/tests/f10_ephemeral_init.sh
docker exec "$SRC" bash -c 'mv /tmp/001[1-5]_*.sql /opt/migrations/'
run "init (0011-0015)" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
run "init repeat" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
expect_fail "extra empty 0016 file" exec "$SRC" bash -c 'touch /opt/migrations/0016_extra_probe.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" rm /opt/migrations/0016_extra_probe.sql
expect_fail "0015 hidden" exec "$SRC" bash -c 'mv /opt/migrations/0015_contract_gap_controls.sql /tmp/; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" mv /tmp/0015_contract_gap_controls.sql /opt/migrations/
expect_fail "unnumbered .sql file" exec "$SRC" bash -c 'touch /opt/migrations/zz_unnumbered.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" rm /opt/migrations/zz_unnumbered.sql

echo "=== baseline suites"
for s in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql; do psqlf "$s"; done
run "API seed (bootstrap: LOGIN roles + installer SERVICE only)" exec "$SRC" bash /opt/tests/f10_ephemeral_seed.sh
run "F10 regression" exec "$SRC" bash /opt/tests/f10_ephemeral_regression.sh
run "C1-C10 probes" exec "$SRC" bash /opt/tests/claude_f10_reaudit_probes.sh
run "R-20 channel/kind" exec "$SRC" bash /opt/tests/f10_v15_channel_kind.sh
run "G1-G5 permanent" exec "$SRC" bash /opt/tests/f10_v15_gap_regression.sh
run "V1.6 T1-T4 contract gaps" exec "$SRC" bash /opt/tests/f10_v16_contract_gaps.sh
psqlf f10_v16_document_trigger.sql

echo "=== D-9 reconciliation (bash equivalent of f10_audit_reconcile.ps1)"
docker logs "$SRC" 2>&1 | grep 'PHOENIX_AUDIT' > "$AUDLOG"
if grep -qE 'Synthetic Renamed|Forbidden Cross Family' "$AUDLOG"; then echo "FAIL display name leaked into PHOENIX_AUDIT"; exit 1; else echo "PASS T1 display names absent from PHOENIX_AUDIT log"; fi
docker exec -e PGPASSFILE=/tmp/f10-backup.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -c 'SELECT attempt_id FROM audit.access_events WHERE attempt_id IS NOT NULL ORDER BY event_id' > "$AUDIDS"
total=$(grep -c 'PHOENIX_AUDIT attempt_id=' "$AUDLOG")
grep -oE 'attempt_id=[0-9a-f-]{36}' "$AUDLOG" | cut -d= -f2 | sort -u > "$AUDLOG.ids"
logonly=$(sort -u "$AUDIDS" | comm -23 "$AUDLOG.ids" - | wc -l)
echo "LOG_ATTEMPTS=$total PERSISTED_MATCHES=$((total-logonly)) LOG_ONLY_ATTEMPTS=$logonly"
sort -u "$AUDIDS" | comm -23 "$AUDLOG.ids" - | while read id; do grep "attempt_id=$id" "$AUDLOG" | sed -E 's/.*(PHOENIX_AUDIT .*) principal_id.*/ROLLED_BACK \1/'; done
if sort -u "$AUDIDS" | comm -23 "$AUDLOG.ids" - | while read id; do grep "attempt_id=$id" "$AUDLOG"; done | grep -q 'resource_id=018f0000-0000-7000-8000-000000009902 decision=DENY'; then echo "PASS D9 rolled-back denial found only in server log"; else echo "FAIL D9 reconciliation"; exit 1; fi
echo "log field check (no names/emails): $(grep -cE '@|Synthetic ' "$AUDLOG") suspicious lines"
rm -f "$AUDLOG.ids"
psqlf f10_d6_immutability_regression.sql
psqlf f10_v15_schema_installer.sql

echo "=== Claude V1.6 probes"
docker exec "$SRC" bash /opt/claude/claude_v16_probes.sh

echo "=== socket / hba / drift / atomic"
docker exec "$SRC" psql -X -w -U phoenix_bootstrap -d phoenix_canonical_dev -Atc 'SELECT 1' 2>&1 | tail -1
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT type||'|'||auth_method FROM pg_hba_file_rules WHERE type IN ('local','host') ORDER BY line_number"
expect_fail "0009 drift" exec "$SRC" bash -c 'printf "\n-- synthetic drift probe\n" >> /opt/migrations/0009_application_write_api.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker cp "$ROOT/migrations/canonical/0009_application_write_api.sql" "$SRC:/opt/migrations/0009_application_write_api.sql" >/dev/null
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/9000_atomicity_probe.sql 2>&1 | grep -o 'ERROR:.*' | head -1
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT 'atomic_schema_exists='||(to_regnamespace('acceptance_atomicity_probe') IS NOT NULL); SELECT 'ledger='||count(*) FROM canonical_migrations.applied;"

echo "=== backup LOGIN dump + fresh-cluster restore"
docker exec "$SRC" bash -c 'set -euo pipefail; umask 077; export PGPASSFILE=/tmp/f10-backup.pgpass; pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -Fc > /f10backup/source.dump; sha256sum /f10backup/source.dump | cut -d" " -f1 > /f10backup/source.dump.sha256; echo "DUMP_SHA=$(cat /f10backup/source.dump.sha256)"; echo "PG_RESTORE_ENTRIES=$(pg_restore -l /f10backup/source.dump | grep -c "^[0-9]*;")"' 2>&1
run "docker run restore --network none" run -d --name "$RST" --network none --env-file "$(cygpath -w "$RENV")" --mount "type=volume,source=$VOL,target=/f10backup,readonly" "$IMG" >/dev/null
wait_db "$RST"; sleep 3
docker exec "$RST" mkdir -p /opt/tests; docker cp "$ROOT/tests/." "$RST:/opt/tests" >/dev/null
run "restore (ledger/tables/policies + suites incl. D6 immutability and T3 trigger)" exec "$RST" bash /opt/tests/f10_ephemeral_restore.sh
docker inspect "$SRC" --format 'SRC NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
docker inspect "$RST" --format 'RST NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "PASS Claude V1.6 closeout re-run PostgreSQL $V (probe findings, if any, are listed above as FINDING lines)"
echo "END $(date '+%F %T %z')"
