#!/usr/bin/env bash
set -euo pipefail
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
family=018f0000-0000-7000-8000-000000000001
tested=0
for kind in FAMILY ADVISOR CHANNEL SERVICE; do
  case "$kind" in
    FAMILY) principal=018f0000-0000-7000-8000-000000002002; actor="'018f0000-0000-7000-8000-000000001002'::uuid"; allowed=FAMILY ;;
    ADVISOR) principal=018f0000-0000-7000-8000-000000002004; actor="'018f0000-0000-7000-8000-000000001004'::uuid"; allowed=ADVISOR ;;
    CHANNEL) principal=018f0000-0000-7000-8000-000000002005; actor="'018f0000-0000-7000-8000-000000001005'::uuid"; allowed=PARTNER ;;
    SERVICE) principal=018f0000-0000-7000-8000-000000002001; actor=NULL; allowed=INTERNAL ;;
  esac
  for channel in FAMILY ADVISOR PARTNER INTERNAL; do
    [ "$channel" = "$allowed" ] && continue
    if output="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$principal',$actor,'$family','$channel',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$principal')" 2>&1)"; then
      echo "FAIL R20 $kind->$channel accepted"; exit 1
    fi
    if [[ "$output" != *CONTEXT_PRINCIPAL_CHANNEL_MISMATCH* ]]; then
      echo "FAIL R20 $kind->$channel wrong reason: $output"; exit 1
    fi
    echo "PASS R20 $kind->$channel refused CONTEXT_PRINCIPAL_CHANNEL_MISMATCH"
    tested=$((tested+1))
  done
done
test "$tested" -eq 12
echo 'PASS R20 all twelve mismatched principal/channel combinations'
