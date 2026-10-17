#!/usr/bin/env bash
# FD-7 rule 5: daily extraction of PHOENIX_AUDIT lines from the PostgreSQL server log into append-only
# files audit/<YYYY-MM-DD>.audit (0600) with a SHA-256 hash chain in audit/chain.txt:
#   <date> <file_sha256> <previous_chain_hash> <chain_hash>,  chain_hash = sha256("<prev> <date> <file_sha>")
# Lines contain IDs and codes only (no names, contents or credentials). Retention: at least 180 days
# (nothing here deletes extracted files). An existing day is never rewritten.
# Usage: ./audit_extract.sh                 extract every completed day not yet extracted
#        ./audit_extract.sh --date YYYY-MM-DD   extract one day (today allowed for drills; it is then closed)
#        ./audit_extract.sh --verify         recompute every file hash and the chain
set -euo pipefail
umask 077
cd "$(dirname "$0")"
mkdir -p audit; chmod 700 audit
chain=audit/chain.txt; touch "$chain"
zero="$(printf '0%.0s' $(seq 1 64))"
last_chain() { tail -n 1 "$chain" | awk '{print $4}'; }
verify() {
  local prev="$zero" ok=1 n=0
  while read -r day fsha p c; do
    n=$((n+1))
    [ "$p" = "$prev" ] || { echo "CHAIN_BROKEN $day previous-hash mismatch"; ok=0; }
    [ -f "audit/$day.audit" ] || { echo "CHAIN_BROKEN $day file missing"; ok=0; prev="$c"; continue; }
    [ "$(sha256sum "audit/$day.audit" | awk '{print $1}')" = "$fsha" ] || { echo "CHAIN_BROKEN $day file hash mismatch"; ok=0; }
    [ "$(printf '%s %s %s' "$p" "$day" "$fsha" | sha256sum | awk '{print $1}')" = "$c" ] || { echo "CHAIN_BROKEN $day chain hash mismatch"; ok=0; }
    prev="$c"
  done < "$chain"
  for f in audit/*.audit; do [ -e "$f" ] || continue; d="$(basename "$f" .audit)"; grep -q "^$d " "$chain" || { echo "CHAIN_BROKEN $d file not in chain"; ok=0; }; done
  [ $ok = 1 ] && echo "CHAIN_OK days=$n" || { echo "CHAIN_FAILED"; return 1; }
}
extract_day() {
  local day="$1" logfile="log/postgresql-$1.log" out="audit/$1.audit" tmp
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "invalid date $day" >&2; return 2; }
  if grep -q "^$day " "$chain"; then echo "SKIP $day already extracted"; return 0; fi
  tmp="$(mktemp)"
  docker compose --env-file .env exec -T postgres sh -c "cat \"\$PGDATA/$logfile\" 2>/dev/null" | grep 'PHOENIX_AUDIT' > "$tmp" || true
  mv "$tmp" "$out"; chmod 400 "$out"
  local fsha prev c; fsha="$(sha256sum "$out" | awk '{print $1}')"; prev="$(last_chain)"; prev="${prev:-$zero}"
  c="$(printf '%s %s %s' "$prev" "$day" "$fsha" | sha256sum | awk '{print $1}')"
  echo "$day $fsha $prev $c" >> "$chain"
  echo "EXTRACTED $day lines=$(wc -l < "$out") sha256=$fsha"
}
case "${1:-}" in
  --verify) verify ;;
  --date) extract_day "${2:?date required}" ;;
  "")
    today="$(date -u +%Y-%m-%d)"
    for f in $(docker compose --env-file .env exec -T postgres sh -c 'ls "$PGDATA/log" 2>/dev/null' | tr -d '\r' | grep -E '^postgresql-[0-9-]{10}\.log$' | sort); do
      day="${f#postgresql-}"; day="${day%.log}"
      [ "$day" \< "$today" ] && extract_day "$day"
    done
    verify ;;
  *) echo "usage: $0 [--date YYYY-MM-DD | --verify]" >&2; exit 2 ;;
esac
