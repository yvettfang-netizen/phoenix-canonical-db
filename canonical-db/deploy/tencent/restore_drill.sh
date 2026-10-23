#!/usr/bin/env bash
# FD-7 rule 4: restore drill. Restores the newest verified backup into a disposable container
# (--network none, no ports, random synthetic bootstrap password), checks the migration ledger
# against the migration files, table and policy counts, records the elapsed time (RTO measurement)
# in drills/, and removes the container. It never touches the running database or its volume.
# Usage: ./restore_drill.sh [backups/<dump>.dump]
set -uo pipefail
umask 077
cd "$(dirname "$0")"
mkdir -p drills; chmod 700 drills
start_s="$(date +%s)"; stamp="$(date -u +%Y%m%dT%H%M%SZ)"; report="drills/drill-$stamp.txt"
exec > >(tee "$report") 2>&1
fail() { echo "RESULT=FAIL $*"; echo "ELAPSED_SECONDS=$(( $(date +%s) - start_s ))"; exit 1; }
# Default only to regular timestamped runtime backups. Pre-upgrade snapshots use a descriptive
# suffix and remain available when passed explicitly, but must not outrank the newest runtime dump.
backup="${1:-$(find backups -maxdepth 1 -type f -name 'phoenix_canonical_[0-9]*.dump' -printf '%T@ %p\n' 2>/dev/null |
  sort -nr | cut -d' ' -f2- | while IFS= read -r d; do [ -f "$d.verified" ] && { echo "$d"; break; }; done)}"
[ -n "$backup" ] && [ -f "$backup" ] || fail "no verified backup found"
manifest_line="$(cat "$backup.manifest.json" 2>/dev/null)"
[[ "$manifest_line" =~ \"sha256\":\"([0-9a-f]{64})\" ]] || fail "manifest missing or invalid"
[ "${BASH_REMATCH[1]}" = "$(sha256sum "$backup" | awk '{print $1}')" ] || fail "manifest digest mismatch"
image="$(awk '/^[[:space:]]*image:/ {print $2; exit}' compose.yaml)"
[[ "$image" == *@sha256:* ]] || fail "compose image is not pinned by digest"
name="phoenix-restore-drill-$stamp-$RANDOM"
envfile="$(mktemp)"; trap 'docker rm -f -v "$name" >/dev/null 2>&1; rm -f "$envfile"' EXIT
printf 'POSTGRES_DB=phoenix_canonical_dev\nPOSTGRES_USER=phoenix_bootstrap\nPOSTGRES_PASSWORD=%s\nPOSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256\n' \
  "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$envfile"
echo "DRILL $stamp backup=$backup image=$image"
envarg="$envfile"; command -v cygpath >/dev/null 2>&1 && envarg="$(cygpath -w "$envfile")"   # git-bash rehearsal hosts
docker run -d --name "$name" --network none --env-file "$envarg" "$image" >/dev/null || fail "docker run"
for _ in $(seq 1 60); do docker exec "$name" pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev >/dev/null 2>&1 && break; sleep 1; done
sleep 2
docker exec "$name" sh -c 'umask 077; printf "*:*:*:phoenix_bootstrap:%s\n" "$POSTGRES_PASSWORD" > /tmp/drill.pgpass' || fail "pgpass"
q() { docker exec -e PGPASSFILE=/tmp/drill.pgpass "$name" psql -X -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
q -c "DO \$r\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_migrator') THEN CREATE ROLE phoenix_canonical_migrator NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_app') THEN CREATE ROLE phoenix_canonical_app NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_reader') THEN CREATE ROLE phoenix_canonical_reader NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='phoenix_canonical_context_binder') THEN CREATE ROLE phoenix_canonical_context_binder NOLOGIN NOINHERIT; END IF;
END \$r\$;" >/dev/null || fail "role bootstrap"
docker cp "$backup" "$name:/tmp/drill.dump" >/dev/null || fail "copy dump"
docker exec -e PGPASSFILE=/tmp/drill.pgpass "$name" pg_restore -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev --no-owner --exit-on-error /tmp/drill.dump || fail "pg_restore"
ledger="$(q -c "SELECT migration_name||' '||sha256 FROM canonical_migrations.applied ORDER BY migration_name")" || fail "ledger read"
files="$(for m in ../../migrations/canonical/[0-9][0-9][0-9][0-9]_*.sql; do echo "$(basename "$m") $(sha256sum "$m" | awk '{print $1}')"; done)"
if [ "$ledger" = "$files" ]; then echo "LEDGER_MATCHES_MIGRATION_FILES count=$(wc -l <<<"$ledger")"; else
  echo "LEDGER_DIFF:"; diff <(echo "$ledger") <(echo "$files") | sed 's/^/  /'; fail "ledger does not match the migration files"; fi
q -c "SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning');
      SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning');
      SELECT 'families='||count(*) FROM core.families; SELECT 'audit_rows='||count(*) FROM audit.access_events;" || fail "catalog read"
docker inspect "$name" --format 'NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}'
echo "RESULT=PASS"
echo "ELAPSED_SECONDS=$(( $(date +%s) - start_s ))"
