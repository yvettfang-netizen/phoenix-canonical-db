#!/usr/bin/env bash
# FD-7 rule 2: local retention 14 days, always keeping the newest 3 verified backups.
# Default is a dry run that only lists what would be removed; pass --apply to delete.
# Usage: ./prune_backups.sh [--apply] [--days N] [--keep N]
set -euo pipefail
umask 077
cd "$(dirname "$0")"
apply=0; days=14; keep=3
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --days) shift; days="$1" ;;
    --keep) shift; keep="$1" ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done
[[ "$days" =~ ^[0-9]+$ ]] && [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 3 ] || { echo "days must be a number and keep >= 3" >&2; exit 2; }
[ -d backups ] || { echo "no backups directory"; exit 0; }
cutoff="$(date -u -d "-$days days" +%Y%m%dT%H%M%SZ)"
# Backup file names carry the UTC creation stamp: backups/phoenix_canonical_<stamp>.dump
# Pre-upgrade snapshots use descriptive names and are governed by the upgrade evidence lifecycle.
# Runtime retention only considers the strict UTC timestamp naming convention produced by backup.sh.
mapfile -t all < <(find backups -maxdepth 1 -type f -name 'phoenix_canonical_[0-9]*.dump' -print 2>/dev/null | sort)
mapfile -t verified < <(for d in "${all[@]}"; do [ -f "$d.verified" ] && [ -f "$d.manifest.json" ] && echo "$d"; done | sort)
protected=" $(printf '%s\n' "${verified[@]}" | tail -n "$keep" | tr '\n' ' ') "
echo "PRUNE mode=$([ $apply = 1 ] && echo apply || echo dry-run) days=$days keep_newest_verified=$keep cutoff_utc=$cutoff total=${#all[@]} verified=${#verified[@]}"
removed=0
for d in "${all[@]}"; do
  stamp="$(basename "$d" .dump)"; stamp="${stamp#phoenix_canonical_}"
  [[ "$stamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "SKIP unexpected name $d"; continue; }
  if [[ "$protected" == *" $d "* ]]; then echo "KEEP $d (newest verified)"; continue; fi
  if [[ "$stamp" < "$cutoff" ]]; then
    if [ $apply = 1 ]; then rm -f -- "$d" "$d.manifest.json" "$d.verified"; echo "REMOVED $d"; else echo "WOULD_REMOVE $d"; fi
    removed=$((removed+1))
  else
    echo "KEEP $d (within $days days)"
  fi
done
echo "PRUNE done candidates=$removed"
