#!/usr/bin/env bash
set -euo pipefail
umask 077

root=/home/ubuntu/phoenix-canonical-db-deploy
deploy="$root/deploy/tencent"

echo "PHASE=B0_READ_ONLY"
echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "user=$(whoami)"
echo "host=$(hostname)"
uname -srmo
df -h /
docker version --format 'docker_client={{.Client.Version}} docker_server={{.Server.Version}} os={{.Server.Os}} arch={{.Server.Arch}}'
docker compose version

test -d "$root"
test -d "$deploy"
cd "$deploy"
test -f .env
echo "env_mode=$(stat -c %a .env)"
test "$(stat -c %a .env)" = 600
echo "env_keys:"
awk -F= '/^[A-Z0-9_]+=/ {print $1}' .env | sort

echo "canonical_containers:"
docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' | grep -E 'phoenix|canonical|tencent-postgres' || true
echo "canonical_volumes:"
docker volume ls --format '{{.Name}}' | grep -E 'phoenix|canonical' || true
echo "container_port_mapping:"
docker port tencent-postgres-1 || true
echo "container_inspect:"
docker inspect tencent-postgres-1 --format 'name={{.Name}} image={{.Config.Image}} image_id={{.Image}} network={{.HostConfig.NetworkMode}} port_bindings={{json .HostConfig.PortBindings}} mounts={{range .Mounts}}{{.Type}}:{{.Name}}:{{.Destination}};{{end}} restart={{.HostConfig.RestartPolicy.Name}}'
echo "host_listeners:"
ss -lnt

echo "tracked_payload_files:"
find "$root/migrations/canonical" "$deploy" -maxdepth 1 -type f \
  ! -name '.env' ! -name '*.dump' ! -name '*.json' ! -name '*.verified' \
  -printf '%m %s %p\n' | sort
echo "tracked_payload_sha256:"
find "$root/migrations/canonical" "$deploy" -maxdepth 1 -type f \
  ! -name '.env' ! -name '*.dump' ! -name '*.json' ! -name '*.verified' \
  -print0 | sort -z | xargs -0 sha256sum

set -a
. ./.env
set +a
test "${PHOENIX_DB_NAME:-}" = phoenix_canonical_dev
test "${PHOENIX_DB_BOOTSTRAP_PASSWORD:-}" != ""
pgpass=/tmp/phoenix-v116-b0.pgpass
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$pgpass'; chmod 600 '$pgpass'"
cleanup() {
  docker compose --env-file .env exec -T postgres rm -f "$pgpass" >/dev/null 2>&1 || true
}
trap cleanup EXIT
psqlq() {
  docker compose --env-file .env exec -T -e "PGPASSFILE=$pgpass" postgres \
    psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 "$@" </dev/null
}

echo "database_catalog:"
psqlq -Atqc "SELECT 'database='||current_database(); SELECT 'version='||current_setting('server_version'); SELECT 'ledger='||count(*) FROM canonical_migrations.applied; SELECT migration_name||'|'||sha256 FROM canonical_migrations.applied ORDER BY migration_name; SELECT 'session_contexts='||count(*) FROM auth.session_contexts; SELECT 'context_tickets='||CASE WHEN to_regclass('auth.context_exchange_tickets') IS NULL THEN 0 ELSE (xpath('/row/n/text()', query_to_xml('SELECT count(*) AS n FROM auth.context_exchange_tickets',false,true,'')))[1]::text::int END;"
echo "hba_rules:"
psqlq -Atqc "SELECT type||'|'||coalesce(database::text,'')||'|'||coalesce(user_name::text,'')||'|'||coalesce(address,'')||'|'||auth_method FROM pg_hba_file_rules ORDER BY line_number;"
echo "runtime_roles:"
psqlq -Atqc "SELECT rolname||'|login='||rolcanlogin||'|super='||rolsuper||'|createdb='||rolcreatedb||'|createrole='||rolcreaterole||'|bypassrls='||rolbypassrls FROM pg_roles WHERE rolname LIKE 'phoenix_%' ORDER BY rolname;"

echo "domain_table_counts:"
total=0
while IFS='|' read -r schema_name table_name; do
  count="$(psqlq -Atqc "SELECT count(*) FROM \"$schema_name\".\"$table_name\";")"
  echo "$schema_name.$table_name=$count"
  total=$((total + count))
done < <(psqlq -Atqc "SELECT schemaname||'|'||tablename FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning') ORDER BY 1;")
echo "DOMAIN_ROWS_TOTAL=$total"
echo "RESULT=PASS_B0_READ_ONLY"
