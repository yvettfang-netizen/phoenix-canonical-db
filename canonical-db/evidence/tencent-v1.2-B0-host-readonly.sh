#!/usr/bin/env bash
set -euo pipefail
printf 'COMMAND whoami; hostname; date -u\n'
whoami
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
printf 'COMMAND docker ps -a\n'
docker ps -a
printf 'COMMAND docker port tencent-postgres-1 (empty required)\n'
docker port tencent-postgres-1
printf 'COMMAND docker inspect selected fields (no environment)\n'
docker inspect --format 'name={{.Name}} image_ref={{.Config.Image}} image_id={{.Image}} network={{json .NetworkSettings.Networks}} port_bindings={{json .HostConfig.PortBindings}} mounts={{json .Mounts}}' tencent-postgres-1
printf 'COMMAND docker volume ls canonical names\n'
docker volume ls --format '{{.Name}}' | grep -i canonical || true
printf 'COMMAND ss -lnt\n'
ss -lnt
printf 'COMMAND list deployment directory metadata, no file contents\n'
if [ -d /home/ubuntu/phoenix-canonical-db-deploy ]; then
  find /home/ubuntu/phoenix-canonical-db-deploy -maxdepth 3 -printf '%P|%m|%s\n' | sort
else
  printf 'DEPLOYMENT_DIRECTORY_MISSING\n'
fi
printf 'COMMAND list old directory metadata, no file contents\n'
if [ -d /home/ubuntu/phoenix-canonical-db ]; then
  find /home/ubuntu/phoenix-canonical-db -maxdepth 2 -printf '%P|%m|%s\n' | sort
else
  printf 'OLD_DIRECTORY_MISSING\n'
fi
# END: absorbs the Windows shell's final CRLF when streamed over SSH.
