#!/usr/bin/env bash
# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
# Run pull.sh + review git diff before pushing.
# Usage: push.sh [-backup] [CONN] [APP]
#   -backup  full split export of the CURRENT target app into tmp/ before
#            importing (minutes on a big app; git already holds the last
#            pulled state, so this is belt-and-braces, not required).
# Gates, in order:
#   1. drift: `apex list -changesSince <last pull date>` - a Builder edit
#      made after your pull would be silently erased by the import.
#   2. validate: skipped when the tree hash matches the stamp written by
#      the last successful apex-validate.sh run (the import still
#      validates server-side regardless).
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"

BACKUP=0
if [[ "${1:-}" == "-backup" ]]; then BACKUP=1; shift; fi
CONN="${1:-__CONN__}"
APP="${2:-__APP__}"
APP_ID="__APP_ID__"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- gate 1: drift since last pull -----------------------------------------
# Date granularity is one day, so pushes on the pull day can list your own
# activity - that is why this asks instead of refusing outright.
PULLSTAMP="$REPO/tmp/.pulled-$APP"
if [[ -f "$PULLSTAMP" ]]; then
  SINCE="$(cat "$PULLSTAMP")"
  echo "== drift check: Builder changes since last pull ($SINCE) =="
  DRIFT="$(sql -name "$CONN" <<SQLEOF
apex list -changesSince $SINCE
exit
SQLEOF
)"
  if grep -q "$APP_ID" <<< "$DRIFT"; then
    echo "$DRIFT"
    echo
    echo "WARNING: app $APP_ID changed in the Builder on/after $SINCE."
    echo "If that was someone else (or you, in the Builder), STOP: pull,"
    echo "diff, and merge first - the import ERASES those changes."
    echo "If it is only your own pull/push activity from that day, continue."
    # prompt echoed to stdout (not read -p) so it also shows in gui.py
    echo -n "Continue push anyway? [y/N] "
    read -r ans
    [[ "$ans" == y* || "$ans" == Y* ]] || { echo "push aborted." >&2; exit 1; }
  else
    echo "no Builder changes since last pull."
  fi
else
  echo "NOTE: no pull stamp (tmp/.pulled-$APP) - cannot check Builder drift."
  echo -n "Continue without the drift check? [y/N] "
  read -r ans
  [[ "$ans" == y* || "$ans" == Y* ]] || { echo "push aborted." >&2; exit 1; }
fi

# ---- optional: backup the current target before replacing it ---------------
if [[ $BACKUP -eq 1 ]]; then
  BK="$REPO/tmp/backup-$APP-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BK"
  echo "== backing up current app $APP_ID to $BK (split export) =="
  sql -name "$CONN" <<SQLEOF
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $APP_ID -dir "$BK" -split -skipExportDate
exit success
SQLEOF
  [[ -f "$BK/f$APP_ID/install.sql" ]] \
    || { echo "backup export incomplete - not importing" >&2; exit 1; }
fi

# ---- gate 2: validate (cache-skip on unchanged tree) ------------------------
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
  # target now equals the repo, so today becomes the new drift baseline
  date +%F > "$PULLSTAMP"
  echo "Imported. Smoke-test in the browser, then pull.sh + commit."
  echo "NOTE: the import disabled any scheduled jobs in the target app."
  echo "      Dev apps: usually fine. PRODUCTION promote: run the manual"
  echo "      re-enable scripts - see scripts/prod-promote/README.md"
else
  echo "IMPORT DID NOT SUCCEED - read the output above. Nothing was replaced." >&2
  exit 1
fi
