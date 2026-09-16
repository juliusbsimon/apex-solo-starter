#!/usr/bin/env bash
# Builder -> repo. Run before editing anything, and after Builder work.
set -euo pipefail
# Claude Code / cron shells do not source .bashrc - find SQLcl ourselves
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
CONN="${1:-__CONN__}"
APP_ID="${2:-__APP_ID__}"
APP="${3:-__APP__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$REPO/tmp/apex-pull"

# Uncommitted edits under apex/ would be OVERWRITTEN by the mirror below.
# Iron rule 1 enforced: commit (or push) first, or say yes knowingly.
if [[ -n "$(git -C "$REPO" status --porcelain -- "apex/$APP" 2>/dev/null)" ]]; then
  echo "WARNING: uncommitted changes under apex/$APP - this pull will ERASE them:"
  git -C "$REPO" status --short -- "apex/$APP"
  echo "Commit first (or push your edits), unless you mean to discard them."
  echo -n "Overwrite local edits with the Builder version? [y/N] "
  read -r ans
  [[ "$ans" == y* || "$ans" == Y* ]] || { echo "pull aborted." >&2; exit 1; }
fi

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

# stamp the pull date: push.sh checks `apex list -changesSince <this>` so a
# Builder edit made after this pull is caught before an import clobbers it
date +%F > "$REPO/tmp/.pulled-$APP"

cd "$REPO" && git status --short
