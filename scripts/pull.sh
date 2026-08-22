#!/usr/bin/env bash
# Builder -> repo. Run before editing anything, and after Builder work.
set -euo pipefail
CONN="${1:-__CONN__}"
APP_ID="${2:-__APP_ID__}"
APP="${3:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$REPO/tmp/apex-pull"

rm -rf "$STAGE"; mkdir -p "$STAGE"

sql -name "$CONN" <<SQLEOF
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $APP_ID -dir "$STAGE" -exptype apexlang -force
exit success
SQLEOF

# APEXlang fallback (ORA-01403 in WWV_META_META_DATA = a component with
# incomplete metadata, see RUNBOOK troubleshooting). Swap the export line for:
#   apex export -applicationid $APP_ID -dir "$STAGE" -split -skipExportDate
# and the guard below for:  [[ -f "$SRC/install.sql" && -d "$SRC/application" ]]

SRC="$(find "$STAGE" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ -z "$SRC" || ! -f "$SRC/application.apx" ]]; then
  echo "export incomplete - not mirroring" >&2; exit 1
fi

mkdir -p "$REPO/apex/$APP"
rsync -a --delete "$SRC/" "$REPO/apex/$APP/"

cd "$REPO" && git status --short
