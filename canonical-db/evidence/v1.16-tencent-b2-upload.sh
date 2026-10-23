#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/home/ubuntu/phoenix-canonical-db-deploy
upload=/home/ubuntu/.phoenix-v116-upload.tar
manifest=/home/ubuntu/.phoenix-v116-upload.sha256
expected_tar_sha=3e015325c8d2819957c5170db106299bbca237b49cdb47ac2f95de7a77f76b9b
test -f "$upload"
test -f "$manifest"
chmod 600 "$upload" "$manifest"
actual_tar_sha="$(sha256sum "$upload" | awk '{print $1}')"
test "$actual_tar_sha" = "$expected_tar_sha"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
stage="/home/ubuntu/.phoenix-v116-stage-$stamp"
snapshot="${root}.bak-v116-$stamp"
test ! -e "$stage"
test ! -e "$snapshot"
mkdir -p "$stage"
tar -xf "$upload" -C "$stage" --strip-components=1
test ! -e "$stage/deploy/tencent/.env"
test "$(find "$stage/migrations/canonical" "$stage/deploy/tencent" -type f | wc -l)" -eq "$(wc -l < "$manifest")"
cp "$manifest" "$stage/upload.sha256"
(cd "$stage" && sha256sum -c upload.sha256)

echo "snapshot_source=$root"
echo "snapshot_target=$snapshot"
cp -a "$root" "$snapshot"
echo "snapshot_env_mode=$(stat -c %a "$snapshot/deploy/tencent/.env")"

mkdir -p "$root/migrations/canonical" "$root/deploy/tencent"
cp -a "$stage/migrations/canonical/." "$root/migrations/canonical/"
cp -a "$stage/deploy/tencent/." "$root/deploy/tencent/"
chmod 600 "$root/deploy/tencent/.env"
chmod 700 "$root/deploy/tencent/"*.sh
(cd "$root" && sha256sum -c "$manifest")

cr_bytes="$(find "$root/migrations/canonical" "$root/deploy/tencent" -maxdepth 1 -type f \
  \( -name '*.sh' -o -name '*.sql' -o -name '*.yaml' -o -name '*.yml' \) -print0 |
  xargs -0 cat | tr -cd '\r' | wc -c)"
test "$cr_bytes" -eq 0
echo "uploaded_head=7b620344af7f87b1a0d882c5f6ae251432440382"
echo "payload_files=$(wc -l < "$manifest")"
echo "tar_sha256=$actual_tar_sha"
echo "cr_bytes=$cr_bytes"
echo "env_mode=$(stat -c %a "$root/deploy/tencent/.env")"
echo "RESULT=PASS_B2_UPLOAD"
rm -rf -- "$stage"
rm -f -- "$upload" "$manifest"
