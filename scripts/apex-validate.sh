#!/usr/bin/env bash
# Validates the APEXlang sources. No DB connection needed.
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
APP="${1:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(sql /nolog <<SQLEOF
apex validate -input $REPO/apex/$APP
exit
SQLEOF
)"
echo "$OUT"
if ! grep -q "Validation successful" <<< "$OUT"; then
  echo
  echo "== findings per file =="
  # SQLcl prints "File: <path>" and "Error:/Warning:" on SEPARATE lines -
  # attribute each finding to the most recent File: line (field-tested)
  awk '/^File:/ { f=$2 }
       /^(Error|Warning):/ && f != "" { c[f]++; if ($1=="Error:") e[f]++ }
       END { for (k in c) printf "%6d  %s%s\n", c[k], k, (e[k] ? " (" e[k] " errors)" : " (warnings only)") }' <<< "$OUT" | sort -rn
  exit 1
fi
