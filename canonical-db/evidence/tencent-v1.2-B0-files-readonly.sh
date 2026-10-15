#!/usr/bin/env bash
set -euo pipefail
cd /home/ubuntu/phoenix-canonical-db-deploy
printf 'COMMAND sha256sum of deployed source files; .env and backups excluded\n'
find migrations/canonical deploy/tencent -type f ! -name '.env' ! -path 'deploy/tencent/backups/*' -print0 |
  sort -z | xargs -0 sha256sum
printf 'COMMAND list existing backups: path, mode, size\n'
find deploy/tencent/backups -maxdepth 1 -type f -printf '%p|%m|%s\n' | sort
printf 'COMMAND sha256sum existing backup files and manifests\n'
find deploy/tencent/backups -maxdepth 1 -type f -print0 | sort -z | xargs -0 -r sha256sum
printf 'COMMAND compare dump SHA-256 to manifest when present\n'
python3 - <<'PY'
import glob, hashlib, json, os
for path in sorted(glob.glob('deploy/tencent/backups/*.dump')):
    manifest = path + '.manifest.json'
    if not os.path.isfile(manifest):
        print(f'{path}|MANIFEST_MISSING')
        continue
    with open(path, 'rb') as f:
        actual = hashlib.file_digest(f, 'sha256').hexdigest()
    with open(manifest, encoding='utf-8') as f:
        expected = json.load(f).get('sha256')
    print(f'{path}|manifest_match={actual == expected}')
PY
# END: absorbs the Windows shell's final CRLF when streamed over SSH.
