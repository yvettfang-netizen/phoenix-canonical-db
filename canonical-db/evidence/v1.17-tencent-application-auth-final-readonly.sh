#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/ubuntu/phoenix-canonical-db-deploy/deploy/tencent
set -a
. ./.env
set +a

service_id=018f0000-0000-7000-8000-00000000a001
bootstrap_pgpass=/tmp/phoenix-v117-final-bootstrap.pgpass
cleanup() {
  docker compose --env-file .env exec -T postgres sh -c "rm -f '$bootstrap_pgpass'" >/dev/null 2>&1 || true
}
trap cleanup EXIT
printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" |
  docker compose --env-file .env exec -T postgres sh -c "umask 077; cat > '$bootstrap_pgpass'; chmod 600 '$bootstrap_pgpass'"

echo "HOST=$(hostname)"
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "ENV_MODE=$(stat -c %a .env)"
echo "ENV_BACKUP_MODE=$(stat -c %a .env.bak-v117-20261023T081903Z)"
docker inspect -f 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} PORTS={{json .HostConfig.PortBindings}}' tencent-postgres-1
./health.sh
docker compose --env-file .env exec -T -e "PGPASSFILE=$bootstrap_pgpass" postgres \
  psql -X -h 127.0.0.1 -U phoenix_bootstrap -d "$PHOENIX_DB_NAME" -v ON_ERROR_STOP=1 -Atqc \
  "BEGIN READ ONLY;
   SELECT 'SERVICE_ROWS='||count(*) FROM auth.principals WHERE principal_id='$service_id' AND principal_kind='SERVICE' AND person_id IS NULL AND status='ACTIVE';
   SELECT 'OTHER_PRINCIPALS='||count(*) FROM auth.principals WHERE principal_id<>'$service_id';
   SELECT 'SESSION_CONTEXT_ROWS='||count(*) FROM auth.session_contexts;
   SELECT 'TICKET_ROWS='||count(*) FROM auth.context_exchange_tickets;
   SELECT 'PEOPLE='||count(*) FROM core.people;
   SELECT 'FAMILIES='||count(*) FROM core.families;
   SELECT 'CONSENTS='||count(*) FROM consent.grants;
   SELECT 'CASES='||count(*) FROM casework.cases;
   SELECT 'DOCUMENTS='||count(*) FROM docs.documents;
   SELECT 'EDUCATION_APPLICATIONS='||count(*) FROM education.applications;
   SELECT 'IDENTITY_CASES='||count(*) FROM identity.cases;
   SELECT 'LEARNING_ENROLLMENTS='||count(*) FROM learning.enrollment;
   COMMIT;"
echo 'RESULT=PASS_FINAL_READONLY_AUTH_STATE'
