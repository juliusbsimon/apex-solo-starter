#!/usr/bin/env bash
# Validates the APEXlang sources. No DB connection needed.
# On success, stamps tmp/.validated-<app> with the tree hash so push.sh can
# skip re-validating an identical tree (any edit invalidates automatically).
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
APP="${1:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tree_hash() {
  find "$REPO/apex/$APP" -type f -print0 | sort -z \
    | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

OUT="$(sql /nolog <<SQLEOF
apex validate -input $REPO/apex/$APP
exit
SQLEOF
)"
echo "$OUT"
if grep -q "Validation successful" <<< "$OUT"; then
  mkdir -p "$REPO/tmp"
  tree_hash > "$REPO/tmp/.validated-$APP"
else
  rm -f "$REPO/tmp/.validated-$APP"
  echo
  echo "== findings per file =="
  awk '/^File:/ { f=$2 }
       /^(Error|Warning):/ && f != "" { c[f]++; if ($1=="Error:") e[f]++ }
       END { for (k in c) printf "%6d  %s%s\n", c[k], k, (e[k] ? " (" e[k] " errors)" : " (warnings only)") }' <<< "$OUT" | sort -rn
  exit 1
fi
