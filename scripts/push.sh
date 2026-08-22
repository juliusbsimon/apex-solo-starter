#!/usr/bin/env bash
# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
# Run pull.sh + review git diff before pushing.
set -euo pipefail
CONN="${1:-__CONN__}"
APP="${2:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$REPO/scripts/apex-validate.sh" "$APP" || { echo "validation failed - not importing" >&2; exit 1; }

sql -name "$CONN" <<SQLEOF
whenever sqlerror exit failure
apex import -input $REPO/apex/$APP
exit success
SQLEOF
echo "Imported. Smoke-test in the browser, then pull.sh + commit."
