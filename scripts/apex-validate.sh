#!/usr/bin/env bash
# Validates the APEXlang sources. No DB connection needed.
set -euo pipefail
APP="${1:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(sql /nolog <<SQLEOF
apex validate -input $REPO/apex/$APP
exit
SQLEOF
)"
echo "$OUT"
grep -q "Validation successful" <<< "$OUT"
