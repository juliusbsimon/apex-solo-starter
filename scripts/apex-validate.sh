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
  echo "== errors/warnings per file =="
  awk 'tolower($0) ~ /error|warning/ {
         for (i=1; i<=NF; i++) if ($i ~ /\.apx/) { gsub(/[,:;]$/,"",$i); f[$i]++ }
       }
       END { for (k in f) printf "%6d  %s\n", f[k], k }' <<< "$OUT" | sort -rn
  exit 1
fi
