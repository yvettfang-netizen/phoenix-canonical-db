#!/usr/bin/env bash
# Bash mirror of tests/f10_local_acceptance.ps1 (pwsh unavailable) + Claude independent probes.
# Disposable containers only (--network none, no ports), synthetic env files in the scratchpad, cleaned up at exit.
set -uo pipefail
export MSYS_NO_PATHCONV=1
V="$1"
ROOT="D:/CODEX/01_PHOENIX/01_NOVA/_worktrees/canonical-postgresql-phase1/canonical-db"
AUD="$(cd "$(dirname "$0")" && pwd -W)"
[ "$V" = 16 ] && IMG='postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' || IMG='postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
SRC="claude-f10-src-pg$V-$RANDOM"; RST="claude-f10-rst-pg$V-$RANDOM"; VOL="claude_f10_bak_pg${V}_$RANDOM"
SENV="$AUD/out/f10src$V.env"; RENV="$AUD/out/f10rst$V.env"
cleanup() { docker rm -f "$SRC" "$RST" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; rm -f "$SENV" "$RENV"; }
trap cleanup EXIT
mkenv() { printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$1"; }
wait_db() { for i in $(seq 1 60); do docker exec "$1" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
run() { echo "COMMAND: $1"; shift; docker "$@" 2>&1; local rc=$?; [ $rc -eq 0 ] || { echo "FAILED rc=$rc"; exit $rc; }; }
mkenv "$SENV"; mkenv "$RENV"
echo "TASK=C-reaudit VERSION=$V IMAGE=$IMG $(date '+%F %T %z')"
run "volume create" volume create "$VOL" >/dev/null
run "docker run source" run -d --name "$SRC" --network none --env-file "$(cygpath -w "$SENV" 2>/dev/null || echo "$SENV")" --mount "type=volume,source=$VOL,target=/f10backup" "$IMG" >/dev/null
wait_db "$SRC"; sleep 3
docker exec "$SRC" mkdir -p /opt/migrations /opt/tests /opt/claude
docker cp "$ROOT/migrations/canonical/." "$SRC:/opt/migrations" >/dev/null
docker cp "$ROOT/tests/." "$SRC:/opt/tests" >/dev/null
docker cp "$AUD/sql/claude_f10_probes.sh" "$SRC:/opt/claude/claude_f10_probes.sh" >/dev/null
run "init" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
run "init repeat" exec "$SRC" bash /opt/tests/f10_ephemeral_init.sh
for s in foundation.sql rls_probe.sql docs_probe.sql contract_neutral_probe.sql trusted_context_probe.sql phase3_acceptance.sql; do
  docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f "/opt/tests/$s" >/dev/null 2>&1 && echo "PASS baseline $s" || echo "FAIL baseline $s"
done
run "seed" exec "$SRC" bash /opt/tests/f10_ephemeral_seed.sh
run "codex f10 regression" exec "$SRC" bash /opt/tests/f10_ephemeral_regression.sh
echo "=== Claude independent probes"
docker exec "$SRC" bash /opt/claude/claude_f10_probes.sh 2>&1
echo "=== socket / drift / atomic"
docker exec "$SRC" psql -X -w -U phoenix_bootstrap -d phoenix_canonical_dev -Atc 'SELECT 1' 2>&1 | tail -1
docker exec "$SRC" bash -c 'printf "\n-- synthetic drift probe\n" >> /opt/migrations/0009_application_write_api.sql; bash /opt/tests/f10_ephemeral_init.sh' 2>&1 | grep -E 'DRIFT|SKIP 0009' | tail -2
docker cp "$ROOT/migrations/canonical/0009_application_write_api.sql" "$SRC:/opt/migrations/0009_application_write_api.sql" >/dev/null
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/9000_atomicity_probe.sql 2>&1 | grep -o 'ERROR:.*' | head -1
docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass "$SRC" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -c "SELECT 'atomic_schema_exists='||(to_regnamespace('acceptance_atomicity_probe') IS NOT NULL); SELECT 'ledger='||count(*) FROM canonical_migrations.applied;"
echo "=== backup role dump + fresh-cluster restore"
docker exec "$SRC" bash -c 'set -euo pipefail; umask 077; export PGPASSFILE=/tmp/f10-backup.pgpass; pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -Fc > /f10backup/source.dump; sha256sum /f10backup/source.dump | cut -d" " -f1 > /f10backup/source.dump.sha256; echo "DUMP_SHA=$(cat /f10backup/source.dump.sha256)"' 2>&1
run "docker run restore" run -d --name "$RST" --network none --env-file "$(cygpath -w "$RENV" 2>/dev/null || echo "$RENV")" --mount "type=volume,source=$VOL,target=/f10backup,readonly" "$IMG" >/dev/null
wait_db "$RST"; sleep 3
docker exec "$RST" mkdir -p /opt/tests; docker cp "$ROOT/tests/." "$RST:/opt/tests" >/dev/null
run "restore" exec "$RST" bash /opt/tests/f10_ephemeral_restore.sh
docker inspect "$SRC" --format 'SRC NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "END C-reaudit PostgreSQL $V $(date '+%F %T %z')"
