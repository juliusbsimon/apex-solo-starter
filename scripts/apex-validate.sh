#!/usr/bin/env bash
# Validates the APEXlang sources. No DB connection needed.
#
# Full tree:    apex-validate.sh [app]
#   On success, records the tree as the validated baseline:
#     tmp/.validated-<app>        one hash of the whole tree
#     tmp/.validated-<app>.files  one hash per file (for -changed)
#   push.sh / promote.sh skip re-validating an identical tree.
#
# Changed only: apex-validate.sh -changed [app]      (what push.sh runs)
#   Compares the tree with the baseline, file by file:
#     nothing changed                -> nothing to do
#     only page files changed/added  -> page-subset validation of those pages
#     anything else (shared components, deleted files, no baseline yet)
#                                    -> full validation
#   The baseline is refreshed by a full pass here AND by every successful
#   push import (the server validated the whole app to accept it).
#
# Page subset:  apex-validate.sh -pages p00101 p00102 ...   (APP=<app> to override)
#   Fast iteration loop (~seconds vs ~minutes on big apps): validates a
#   staged copy holding shared components + the global page + ONLY the named
#   pages. NEVER writes the baseline - a page-level pass is not a full-tree
#   pass. What a subset pass cannot see: another page that refers to
#   something you renamed or removed on the edited page. The server-side
#   import checks the whole app and refuses it on any error, so that case
#   fails at push (nothing replaced) rather than slipping through.
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=full
PAGES=()
case "${1:-}" in
  -pages)
    shift; MODE=pages; PAGES=("$@"); APP="${APP:-__APP__}"
    [[ ${#PAGES[@]} -gt 0 ]] || { echo "usage: apex-validate.sh -pages p00101 [p00102 ...]" >&2; exit 2; }
    ;;
  -changed) shift; MODE=changed; APP="${1:-__APP__}" ;;
  *)        APP="${1:-__APP__}" ;;
esac
SRC="$REPO/apex/$APP"
[[ -d "$SRC" ]] || { echo "no such app dir: apex/$APP" >&2; exit 1; }
STAMP="$REPO/tmp/.validated-$APP"
MANIFEST="$STAMP.files"

# same formula as push.sh / promote.sh - keep them identical
tree_hash() { find "$SRC" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1; }
# "<sha256>  ./relative/path" per file
manifest()  { (cd "$SRC" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }

summarize() {
  echo; echo "== findings per file =="
  awk '/^File:/ { f=$2 }
       /^(Error|Warning):/ && f != "" { c[f]++; if ($1=="Error:") e[f]++ }
       END { for (k in c) printf "%6d  %s%s\n", c[k], k, (e[k] ? " (" e[k] " errors)" : " (warnings only)") }' | sort -rn
}

# ---- -changed: decide between nothing / page subset / full -------------------
if [[ $MODE == changed ]]; then
  if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$(tree_hash)" ]]; then
    echo "tree unchanged since the last full validation or successful import - nothing to validate"
    exit 0
  fi
  if [[ ! -f "$MANIFEST" ]]; then
    echo "no per-file baseline yet - full validation this once (later runs only check what changed)"
    MODE=full
  else
    CUR="$(manifest)"
    # lines in CUR but not in the baseline = files added or modified
    CHANGED="$(LC_ALL=C comm -13 <(LC_ALL=C sort "$MANIFEST") <(LC_ALL=C sort <<< "$CUR") | cut -c67-)"
    REMOVED="$(LC_ALL=C comm -23 <(cut -c67- "$MANIFEST" | LC_ALL=C sort) <(cut -c67- <<< "$CUR" | LC_ALL=C sort))"
    NONPAGE="$(grep -vP '^\./pages/p\d+(-[^/]*)?\.apx$' <<< "$CHANGED" || true)"
    if [[ -z "$CHANGED" && -z "$REMOVED" ]]; then
      echo "file contents match the baseline - nothing to validate"
      tree_hash > "$STAMP"          # repo moved/renamed: re-anchor the whole-tree hash
      exit 0
    elif [[ -n "$REMOVED" ]]; then
      echo "files removed since the baseline - full validation:"
      head -5 <<< "$REMOVED" | sed 's/^/   /'
      MODE=full
    elif [[ -n "$NONPAGE" ]]; then
      echo "non-page files changed since the baseline - full validation:"
      head -5 <<< "$NONPAGE" | sed 's/^/   /'
      [[ $(wc -l <<< "$NONPAGE") -gt 5 ]] && echo "   ... and $(( $(wc -l <<< "$NONPAGE") - 5 )) more"
      MODE=full
    else
      mapfile -t PAGES < <(sed -E 's#^\./pages/(p[0-9]+).*#\1#' <<< "$CHANGED" | sort -u)
      echo "only ${#PAGES[@]} page file(s) changed since the baseline - validating just those"
      MODE=pages
    fi
  fi
fi

# ---- page subset --------------------------------------------------------------
if [[ $MODE == pages ]]; then
  STAGE="$REPO/tmp/validate-pages"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  # everything except pages/ (plain find+cp: rsync isn't installed everywhere)
  find "$SRC" -mindepth 1 -maxdepth 1 ! -name pages -exec cp -a {} "$STAGE/" \;
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
  echo "== page-subset validation (${PAGES[*]}) - baseline will NOT be updated =="
  # tee /dev/stderr: stream live AND capture for the check
  OUT="$(sql /nolog <<SQLEOF | tee /dev/stderr
apex validate -input $STAGE
exit
SQLEOF
)"
  if grep -q "Validation successful" <<< "$OUT"; then
    echo "subset OK (the server-side import still checks the whole app)"
  else
    summarize <<< "$OUT"
    exit 1
  fi
  exit 0
fi

# ---- full tree ----------------------------------------------------------------
echo "== validating the full tree ($SRC) - can take minutes on a large app =="
# tee /dev/stderr: stream live (minutes on a big app) AND capture for the check
OUT="$(sql /nolog <<SQLEOF | tee /dev/stderr
apex validate -input $SRC
exit
SQLEOF
)"
if grep -q "Validation successful" <<< "$OUT"; then
  mkdir -p "$REPO/tmp"
  tree_hash > "$STAMP"
  manifest  > "$MANIFEST"
else
  rm -f "$STAMP"   # the per-file baseline stays: it is still the last GOOD tree
  summarize <<< "$OUT"
  exit 1
fi
