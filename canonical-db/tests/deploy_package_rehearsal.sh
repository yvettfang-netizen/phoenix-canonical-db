#!/usr/bin/env bash
# Local rehearsal of the deploy/tencent package: install (twice, idempotent), health, API write through
# the deployed binder/app runtime logins, backup, and restore into a fresh volume, then health again.
# It runs a COPY of the package in a scratch directory; the copy only replaces the registry mirror
# image reference by the identical Docker Hub digest and makes the volume/network names unique.
# No Tencent host, no registry pull (the digest must be cached locally), no published ports.
# Usage: tests/deploy_package_rehearsal.sh <scratch-dir> [evidence-file]
set -uo pipefail
export MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
WORK="${1:?usage: $0 <scratch-dir> [evidence-file]}"
[ -n "${2:-}" ] && exec > >(tee "$2") 2>&1
DIGEST='sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d'
docker image inspect "postgres@$DIGEST" >/dev/null 2>&1 || { echo "FAIL image digest not cached locally; refusing to pull"; exit 1; }
SUFFIX="$(date +%s)$RANDOM"
fail() { echo "FAIL $*"; exit 1; }
mkpkg() { # $1 = package dir name
  local d="$WORK/$1"
  mkdir -p "$d/canonical-db/deploy" "$d/canonical-db/migrations"
  cp -r "$ROOT/deploy/tencent" "$d/canonical-db/deploy/"
  cp -r "$ROOT/migrations/canonical" "$d/canonical-db/migrations/"
  rm -f "$d/canonical-db/deploy/tencent/.env"; rm -rf "$d/canonical-db/deploy/tencent/backups"
  sed -i "s#image: .*#image: postgres@$DIGEST#; s#phoenix_canonical_pg16_data#phoenix_rehearsal_${1}_$SUFFIX#g; s#phoenix_canonical_private#phoenix_rehearsal_net_${1}_$SUFFIX#g" "$d/canonical-db/deploy/tencent/compose.yaml"
  printf '%s\n' "$d/canonical-db/deploy/tencent"
}
hex() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
SRC_PKG="$(mkpkg src)"; RST_PKG="$(mkpkg rst)"
cleanup() {
  (cd "$SRC_PKG" && docker compose -p "rehearsal_src_$SUFFIX" --env-file .env down -v --remove-orphans >/dev/null 2>&1)
  (cd "$RST_PKG" && docker compose -p "rehearsal_rst_$SUFFIX" --env-file .env down -v --remove-orphans >/dev/null 2>&1)
  rm -rf "$WORK/src" "$WORK/rst"
}
trap cleanup EXIT
SVC=018f0000-0000-7000-8000-0000000f0001; FAM=018f0000-0000-7000-8000-0000000f0010
umask 077
{ echo "PHOENIX_DB_NAME=phoenix_canonical_dev"
  for n in BOOTSTRAP MIGRATOR APP READER BINDER BACKUP; do echo "PHOENIX_DB_${n}_PASSWORD=$(hex)"; done
  echo "PHOENIX_DB_SERVICE_PRINCIPAL_ID=$SVC"; echo "PHOENIX_DB_SERVICE_PRINCIPAL_LABEL=rehearsal-management-service"; } > "$SRC_PKG/.env"
cp "$SRC_PKG/.env" "$RST_PKG/.env"
# Both copies live in directories named "tencent"; give each its own compose project (rehearsal only).
echo "COMPOSE_PROJECT_NAME=rehearsal_src_$SUFFIX" >> "$SRC_PKG/.env"
echo "COMPOSE_PROJECT_NAME=rehearsal_rst_$SUFFIX" >> "$RST_PKG/.env"
echo "TASK=deploy package rehearsal HEAD=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null) IMAGE=postgres@$DIGEST $(date '+%F %T %z')"
echo "PACKAGE_DIFF (copy vs repository compose.yaml):"; diff "$ROOT/deploy/tencent/compose.yaml" "$SRC_PKG/compose.yaml" | sed 's/^/  /'

echo "=== 1. install"
(cd "$SRC_PKG" && bash install.sh) 2>&1 | grep -vE '^\s*$' | sed -E 's/ [0-9a-f]{64}$//' ; [ "${PIPESTATUS[0]}" = 0 ] || fail install
echo "=== 2. install again (idempotent)"
out="$(cd "$SRC_PKG" && bash install.sh 2>&1)" || fail "second install"
printf '%s\n' "$out" | grep -E 'APPLIED|service principal|PASS' ; grep -q APPLIED <<<"$out" && fail "second install re-applied a migration"
grep -q 'SKIP service principal' <<<"$out" || fail "second install did not skip the service principal"
echo "PASS second install applied nothing and skipped the service principal"
echo "=== 3. health"
h="$(cd "$SRC_PKG" && bash health.sh 2>&1)"; printf '%s\n' "$h"; grep -q '^migrations=16$' <<<"$h" || fail health

echo "=== 4. API write through the deployed runtime logins (binder ticket -> app)"
dc() { (cd "$SRC_PKG" && docker compose -p "rehearsal_src_$SUFFIX" --env-file .env "$@"); }
rc_() { (cd "$RST_PKG" && docker compose -p "rehearsal_rst_$SUFFIX" --env-file .env "$@"); }
envval() { grep "^$1=" "$2" | cut -d= -f2-; }  # read one value without exporting the file
BINDER_PW="$(envval PHOENIX_DB_BINDER_PASSWORD "$SRC_PKG/.env")"; APP_PW="$(envval PHOENIX_DB_APP_PASSWORD "$SRC_PKG/.env")"
printf '%s\n' "*:*:*:phoenix_canonical_binder_runtime:$BINDER_PW" | dc exec -T postgres sh -c 'umask 077; cat > /tmp/r-binder.pgpass'
printf '%s\n' "*:*:*:phoenix_canonical_app_runtime:$APP_PW" | dc exec -T postgres sh -c 'umask 077; cat > /tmp/r-app.pgpass'
ticket="$(dc exec -T -e PGPASSFILE=/tmp/r-binder.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_binder_runtime -d phoenix_canonical_dev -c "SELECT auth.issue_context_ticket('$SVC',NULL,NULL,'INTERNAL',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$SVC')")" || fail "binder ticket"
w="$(printf "SELECT auth.redeem_context_ticket('%s','%s');\nSELECT 'CREATE_FAMILY='||core.create_family('%s','Rehearsal Family');\nSELECT auth.clear_context();\n" "$ticket" "$SVC" "$FAM" | dc exec -T -e PGPASSFILE=/tmp/r-app.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_app_runtime -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f - 2>&1)"
printf '%s\n' "$w" | grep -E 'CREATE_FAMILY|ERROR'; grep -q 'CREATE_FAMILY=true' <<<"$w" || fail "API write through runtime logins"
direct="$(dc exec -T -e PGPASSFILE=/tmp/r-app.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_app_runtime -d phoenix_canonical_dev -c "INSERT INTO core.families(family_id,display_name) VALUES ('018f0000-0000-7000-8000-0000000f0011','Direct')" 2>&1)"
grep -q 'permission denied' <<<"$direct" && echo "PASS app runtime direct table write denied" || fail "app runtime direct write: $direct"
dc exec -T postgres sh -c 'rm -f /tmp/r-binder.pgpass /tmp/r-app.pgpass'

echo "=== 5. backup"
b="$(cd "$SRC_PKG" && bash backup.sh 2>&1)"; printf '%s\n' "$b"
dump="$(sed -n 's/^BACKUP //p' <<<"$b")"; [ -n "$dump" ] && [ -f "$SRC_PKG/$dump" ] || fail backup
cat "$SRC_PKG/$dump.manifest.json"; echo
echo "=== 6. restore into a fresh volume (separate compose project)"
mkdir -p "$RST_PKG/backups"; chmod 700 "$RST_PKG/backups"
cp "$SRC_PKG/$dump" "$SRC_PKG/$dump.manifest.json" "$RST_PKG/backups/"
(cd "$RST_PKG" && bash restore.sh "$dump") 2>&1 | grep -vE '^\s*$'; [ "${PIPESTATUS[0]}" = 0 ] || fail restore
echo "--- tampered manifest must be refused"
cp "$RST_PKG/$dump" "$RST_PKG/backups/phoenix_canonical_tampered.dump"
sed 's/"sha256":"[0-9a-f]\{4\}/"sha256":"0000/' "$RST_PKG/$dump.manifest.json" > "$RST_PKG/backups/phoenix_canonical_tampered.dump.manifest.json"
t="$(cd "$RST_PKG" && bash restore.sh backups/phoenix_canonical_tampered.dump 2>&1)"; rc=$?
printf '%s\n' "$t" | tail -1; [ $rc -ne 0 ] && grep -q 'digest mismatch' <<<"$t" && echo "PASS tampered backup refused" || fail "tampered backup accepted"
echo "=== 7. health and data after restore"
h="$(cd "$RST_PKG" && bash health.sh 2>&1)"; printf '%s\n' "$h"; grep -q '^migrations=16$' <<<"$h" || fail "health after restore"
BACKUP_PW="$(envval PHOENIX_DB_BACKUP_PASSWORD "$RST_PKG/.env")"
printf '%s\n' "*:*:*:phoenix_canonical_backup_runtime:$BACKUP_PW" | rc_ exec -T postgres sh -c 'umask 077; cat > /tmp/r-backup.pgpass'
r="$(rc_ exec -T -e PGPASSFILE=/tmp/r-backup.pgpass postgres psql -X -At -h 127.0.0.1 -U phoenix_canonical_backup_runtime -d phoenix_canonical_dev -c "SELECT 'families='||count(*) FROM core.families; SELECT 'service_principals='||count(*) FROM auth.principals WHERE principal_kind='SERVICE' AND person_id IS NULL; SELECT 'audit_rows='||count(*) FROM audit.access_events;")"
printf '%s\n' "$r"; grep -q '^families=1$' <<<"$r" && grep -q '^service_principals=1$' <<<"$r" || fail "restored data"
rc_ exec -T postgres sh -c 'rm -f /tmp/r-backup.pgpass'
{ dc ps --format '{{.Name}} {{.Ports}}'; rc_ ps --format '{{.Name}} {{.Ports}}'; } | sed 's/^/CONTAINER_PORTS /'
echo "PASS deploy package rehearsal: install, idempotent re-install, health, runtime API write, backup, verified restore, health"
