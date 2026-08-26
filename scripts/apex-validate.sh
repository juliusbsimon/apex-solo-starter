#!/usr/bin/env bash
# Validates the APEXlang sources. No DB connection needed.
#
# Full tree:    apex-validate.sh [app]
#   On success, stamps tmp/.validated-<app> with the tree hash so push.sh
#   can skip re-validating an identical tree.
#
# Page subset:  apex-validate.sh -pages p00101 p00102 ...   (APP=<app> to override)
#   Fast iteration loop (~seconds vs ~minutes on big apps): validates a
#   staged copy holding shared components + the global page + ONLY the named
#   pages. NEVER writes the stamp - a page-level pass is not a full-tree
#   pass, and stamping it would let push.sh skip validation on a tree that
#   was never fully validated. (It doesn't delete an existing stamp either:
#   push's hash check already invalidates on any tree change.)
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PAGES=()
if [[ "${1:-}" == "-pages" ]]; then
  shift
  PAGES=("$@")
  APP="${APP:-__APP__}"
  [[ ${#PAGES[@]} -gt 0 ]] || { echo "usage: apex-validate.sh -pages p00101 [p00102 ...]" >&2; exit 2; }
else
  APP="${1:-__APP__}"
fi
SRC="$REPO/apex/$APP"

summarize() {
  echo; echo "== findings per file =="
  awk '/^File:/ { f=$2 }
       /^(Error|Warning):/ && f != "" { c[f]++; if ($1=="Error:") e[f]++ }
       END { for (k in c) printf "%6d  %s%s\n", c[k], k, (e[k] ? " (" e[k] " errors)" : " (warnings only)") }' | sort -rn
}

if [[ ${#PAGES[@]} -gt 0 ]]; then
  STAGE="$REPO/tmp/validate-pages"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  rsync -a --exclude 'pages/' "$SRC/" "$STAGE/"
  mkdir -p "$STAGE/pages"
  # page files may be pNNNNN-<slug>.apx OR bare pNNNNN.apx - accept both
  cp "$SRC"/pages/p00000-*.apx "$SRC"/pages/p00000.apx "$STAGE/pages/" 2>/dev/null || true  # global page, if present
  for p in "${PAGES[@]}"; do
    found=0
    for f in "$SRC/pages/${p}.apx" "$SRC"/pages/${p}-*.apx; do
      [[ -f "$f" ]] && { cp "$f" "$STAGE/pages/"; found=1; }
    done
    [[ $found -eq 1 ]] || { echo "no such page file: pages/${p}[-*].apx" >&2; exit 1; }
  done
  echo "== page-subset validation (${PAGES[*]}) - stamp will NOT be written =="
  OUT="$(sql /nolog <<SQLEOF
apex validate -input $STAGE
exit
SQLEOF
)"
  echo "$OUT"
  if grep -q "Validation successful" <<< "$OUT"; then
    echo "subset OK (a full validate or the server-side import still gates the push)"
  else
    summarize <<< "$OUT"
    exit 1
  fi
else
  OUT="$(sql /nolog <<SQLEOF
apex validate -input $SRC
exit
SQLEOF
)"
  echo "$OUT"
  if grep -q "Validation successful" <<< "$OUT"; then
    mkdir -p "$REPO/tmp"
    find "$SRC" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 \
      > "$REPO/tmp/.validated-$APP"
  else
    rm -f "$REPO/tmp/.validated-$APP"
    summarize <<< "$OUT"
    exit 1
  fi
fi
