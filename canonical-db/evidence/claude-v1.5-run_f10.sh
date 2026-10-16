#!/usr/bin/env bash
# Claude V1.4 independent re-run: bash mirror of tests/f10_local_acceptance.ps1 (pwsh unavailable on this host)
# plus Claude gap probes. Disposable containers only (--network none, no ports); synthetic env files kept
# outside the repository and removed at exit.
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="$1"
ROOT="D:/CODEX/01_PHOENIX/01_NOVA/_worktrees/canonical-postgresql-phase1/canonical-db"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SRC="claude-v14-src-pg$V-$RANDOM"; RST="claude-v14-rst-pg$V-$RANDOM"; VOL="claude_v14_bak_pg${V}_$RANDOM"
SENV="$HERE/src$V.env"; RENV="$HERE/rst$V.env"
M11=0011_verified_capacity_official_facts_manifest_confirmation.sql
cleanup() { docker rm -f "$SRC" "$RST" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; rm -f "$SENV" "$RENV"; }
trap cleanup EXIT
mkenv() { printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$1"; }
wait_db() { for i in $(seq 1 60); do docker exec "$1" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
run() { echo "COMMAND: $1"; shift; docker "$@" 2>&1; local rc=$?; [ $rc -eq 0 ] || { echo "FAILED rc=$rc"; exit $rc; }; }
expect_fail() { echo "COMMAND: $1 (expected refusal)"; shift; local out; out="$(docker "$@" 2>&1)"; local rc=$?; printf '%s\n' "$out" | tail -2; if [ $rc -ne 0 ]; then echo "PASS refused rc=$rc"; else echo "FAIL unexpectedly accepted"; exit 1; fi; }
mkenv "$SENV"; mkenv "$RENV"
echo "TASK=Claude-V1.4-reaudit VERSION=$V IMAGE=$IMG HEAD=$(git -C "$ROOT" rev-parse --short HEAD) $(date '+%F %T %z')"
run "volume create" volume create "$VOL" >/dev/null
run "docker run source --network none" run -d --name "$SRC" --network none --env-file "$(cygpath -w "$SENV")" --mount "type=volume,source=$VOL,target=/f10backup" "$IMG" >/dev/null
wait_db "$SRC"; sleep 3
docker exec "$SRC" mkdir -p /opt/migrations /opt/tests /opt/claude
docker cp "$ROOT/migrations/canonical/." "$SRC:/opt/migrations" >/dev/null
docker cp "$ROOT/tests/." "$SRC:/opt/tests" >/dev/null
docker cp "$HERE/claude_v14_d6_probes.sh" "$SRC:/opt/claude/claude_v14_d6_probes.sh" >/dev/null

echo "=== E1: 0001-0010 first (expected=10), then 0011, repeat, inventory guards"
docker exec "$SRC" mv "/opt/migrations/$M11" "/tmp/$M11"
run "init expected=10" exec -e F10_EXPECTED_MIGRATION_COUNT=10 "$SRC" bash /opt/tests/f10_ephemeral_init.sh
docker exec "$SRC" mv "/tmp/$M11" "/opt/migrations/$M11"
run "init (0011)" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
run "init repeat" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
expect_fail "extra empty 0012 file" exec "$SRC" bash -c 'touch /opt/migrations/0012_extra_probe.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" rm /opt/migrations/0012_extra_probe.sql
expect_fail "0011 hidden" exec "$SRC" bash -c "mv /opt/migrations/$M11 /tmp/$M11; bash /opt/tests/f10_ephemeral_init.sh"
docker exec "$SRC" mv "/tmp/$M11" "/opt/migrations/$M11"
expect_fail "unnumbered .sql file in migration dir" exec "$SRC" bash -c 'touch /opt/migrations/zz_unnumbered.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker exec "$SRC" rm /opt/migrations/zz_unnumbered.sql

echo "=== baseline suites"
for s in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql; do
  docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f "/opt/tests/$s" >/dev/null 2>&1 && echo "PASS baseline $s" || { echo "FAIL baseline $s"; exit 1; }
done
run "seed" exec "$SRC" bash /opt/tests/f10_ephemeral_seed.sh
run "Codex F10 regression (D6 sessions included)" exec "$SRC" bash /opt/tests/f10_ephemeral_regression.sh
run "C1-C10 probes (C4/C5/C8 now asserted)" exec "$SRC" bash /opt/tests/claude_f10_reaudit_probes.sh
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/f10_d6_immutability_regression.sql 2>&1 | grep -E 'PASS|ERROR' ; echo "immutability rc=${PIPESTATUS[0]}"
echo "=== Claude V1.4 gap probes"
run "claude_v14_d6_probes.sh" exec "$SRC" bash /opt/claude/claude_v14_d6_probes.sh

echo "=== socket / drift / atomic"
docker exec "$SRC" psql -X -w -U phoenix_bootstrap -d phoenix_canonical_dev -Atc 'SELECT 1' 2>&1 | tail -1
expect_fail "0009 drift" exec "$SRC" bash -c 'printf "\n-- synthetic drift probe\n" >> /opt/migrations/0009_application_write_api.sql; bash /opt/tests/f10_ephemeral_init.sh'
docker cp "$ROOT/migrations/canonical/0009_application_write_api.sql" "$SRC:/opt/migrations/0009_application_write_api.sql" >/dev/null
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/9000_atomicity_probe.sql 2>&1 | grep -o 'ERROR:.*' | head -1
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT 'atomic_schema_exists='||(to_regnamespace('acceptance_atomicity_probe') IS NOT NULL); SELECT 'ledger='||count(*) FROM canonical_migrations.applied;"

echo "=== backup role dump + fresh-cluster restore"
docker exec "$SRC" bash -c 'set -euo pipefail; umask 077; export PGPASSFILE=/tmp/f10-backup.pgpass; pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -Fc > /f10backup/source.dump; sha256sum /f10backup/source.dump | cut -d" " -f1 > /f10backup/source.dump.sha256; echo "DUMP_SHA=$(cat /f10backup/source.dump.sha256)"' 2>&1
run "docker run restore --network none" run -d --name "$RST" --network none --env-file "$(cygpath -w "$RENV")" --mount "type=volume,source=$VOL,target=/f10backup,readonly" "$IMG" >/dev/null
wait_db "$RST"; sleep 3
docker exec "$RST" mkdir -p /opt/tests; docker cp "$ROOT/tests/." "$RST:/opt/tests" >/dev/null
run "restore (asserts ledger=11, tables=26, D6 immutability)" exec "$RST" bash /opt/tests/f10_ephemeral_restore.sh
docker inspect "$SRC" --format 'SRC NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
docker inspect "$RST" --format 'RST NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "END Claude-V1.4-reaudit PostgreSQL $V $(date '+%F %T %z')"
