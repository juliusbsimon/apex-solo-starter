#!/usr/bin/env bash
# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
# Run pull.sh + review git diff before pushing.
# Skips the local pre-validate when the tree hash matches the stamp written
# by the last successful apex-validate.sh run (the import still validates
# server-side regardless - the app only imports when it validates cleanly).
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
CONN="${1:-__CONN__}"
APP="${2:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tree_hash() {
  find "$REPO/apex/$APP" -type f -print0 | sort -z \
    | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

STAMP="$REPO/tmp/.validated-$APP"
if [[ -f "$STAMP" ]] && [[ "$(cat "$STAMP")" == "$(tree_hash)" ]]; then
  echo "tree unchanged since last successful validation - skipping pre-validate"
else
  "$REPO/scripts/apex-validate.sh" "$APP" \
    || { echo "validation failed - not importing" >&2; exit 1; }
fi

# NOTE: `apex` is a SQLcl command, not SQL - `whenever sqlerror` does NOT
# catch its failures. Success is judged from the actual output, and the
# workspace is passed explicitly: on a schema granted to multiple
# workspaces, an import without -workspace bails silently.
OUT="$(sql -name "$CONN" <<SQLEOF
apex import -input $REPO/apex/$APP -workspace __WORKSPACE__
exit
SQLEOF
)"
echo "$OUT"
if grep -qi "import successful" <<< "$OUT"; then
  echo "Imported. Smoke-test in the browser, then pull.sh + commit."
else
  echo "IMPORT DID NOT SUCCEED - read the output above. Nothing was replaced." >&2
  exit 1
fi
