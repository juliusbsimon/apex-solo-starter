#!/usr/bin/env bash
# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
# Run pull.sh + review git diff before pushing.
# Usage: push.sh [-backup] [-full] [-supporting-objects] [CONN] [APP] [APP_ID] [WORKSPACE]
#   Args 2-4 matter in MULTI-APP repos (several dirs under apex/): name the
#   app dir, its application id, and - if it differs - its workspace.
#   No args = the stamped defaults, same as always.
#   -backup  full split export of the CURRENT target app into tmp/ before
#            importing (minutes on a big app; git already holds the last
#            pulled state, so this is belt-and-braces, not required).
#   -full    validate the whole tree even if only pages changed.
#   -supporting-objects
#            also run the app's supporting-object scripts
#            (apex/<APP>/supporting-objects/) in the import session. Off by
#            default: some apps carry full schema install scripts there. It
#            lists the scripts and asks first. See docs/apexlang-notes.md,
#            "Supporting objects".
# Gates, in order:
#   1. drift: `apex list -changesSince <last pull date>` - a Builder edit
#      made after your pull would be silently erased by the import.
#   2. validate: `apex-validate.sh -changed` - nothing if the tree matches
#      the baseline, only the edited pages if nothing but page files
#      changed, the full tree otherwise. The baseline is the last full
#      validation OR the last successful import (the server validates the
#      whole app on import, so an accepted import is a full pass).
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"

BACKUP=0; FULLVAL=0; SUPOBJ=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -backup) BACKUP=1 ;;
    -full)   FULLVAL=1 ;;
    -supporting-objects) SUPOBJ=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
CONN="${1:-__CONN__}"
APP="${2:-__APP__}"
APP_ID="${3:-__APP_ID__}"
WS="${4:-__WORKSPACE__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$REPO/scripts/template-check.sh" 2>/dev/null || true   # one line if the template has updates; never blocks

# ---- gate 1: drift since last pull -----------------------------------------
# Date granularity is one day, so pushes on the pull day can list your own
# activity - that is why this asks instead of refusing outright.
PULLSTAMP="$REPO/tmp/.pulled-$APP"
if [[ -f "$PULLSTAMP" ]]; then
  SINCE="$(cat "$PULLSTAMP")"
  echo "== drift check: Builder changes since last pull ($SINCE) =="
  echo "   (SQLcl takes ~10s to start - output streams when it does)"
  # tee /dev/stderr: stream live AND capture for the gate below
  DRIFT="$(sql -name "$CONN" <<SQLEOF | tee /dev/stderr
apex list -changesSince $SINCE
exit
SQLEOF
)"
  if grep -qP "(^|\s)$APP_ID(\s|$)" <<< "$DRIFT"; then   # whole column, not a substring (10 must not match 100)
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
set define off
whenever oserror  exit failure
apex export -applicationid $APP_ID -dir "$BK" -split -skipExportDate
exit success
SQLEOF
  [[ -f "$BK/f$APP_ID/install.sql" ]] \
    || { echo "backup export incomplete - not importing" >&2; exit 1; }
fi

# ---- gate 2: validate only what changed since the baseline -----------------
# same formulas as apex-validate.sh - keep them identical
SRC="$REPO/apex/$APP"
tree_hash() { find "$SRC" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1; }
manifest()  { (cd "$SRC" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }

if [[ $FULLVAL -eq 1 ]]; then
  echo "== -full: validating the whole tree before import =="
  "$REPO/scripts/apex-validate.sh" "$APP" \
    || { echo "validation failed - not importing" >&2; exit 1; }
else
  "$REPO/scripts/apex-validate.sh" -changed "$APP" \
    || { echo "validation failed - not importing" >&2; exit 1; }
fi

# ---- optional: supporting-object scripts ------------------------------------
# `apex import` never runs them by itself; they run only when the SAME SQLcl
# session first calls set_auto_install_sup_obj(true). Opt-in on purpose.
SO="$SRC/supporting-objects"
SUPOBJ_SQL=""
if [[ -d "$SO" ]]; then
  if [[ $SUPOBJ -eq 1 ]]; then
    echo "== supporting objects: these scripts will run in the app's schema, after the import =="
    found=0
    for f in "$SO"/install-scripts/*.sql "$SO"/upgrade-scripts/*.sql; do
      [[ -f "$f" ]] && { echo "   ${f#"$SO"/}"; found=1; }
    done
    [[ $found -eq 1 ]] || echo "   (no .sql files found - APEX may still run inline scripts from the .apx files)"
    if grep -q "upgradeWhenSqlQuery" "$SO/supporting-objects.apx" 2>/dev/null; then
      echo "   NOTE: supporting-objects.apx has an upgrade query. If it returns a row, the"
      echo "   UPGRADE scripts run and the install scripts do not - even for a new app."
    fi
    echo "   They run on every push with this option, so they must be safe to run again."
    echo "   A failing statement is skipped SILENTLY and the import still says it succeeded."
    echo -n "Run these supporting-object scripts? [y/N] "
    read -r ans
    [[ "$ans" == y* || "$ans" == Y* ]] || { echo "push aborted (push again without -supporting-objects to skip them)." >&2; exit 1; }
    SUPOBJ_SQL="exec apex_application_install.set_auto_install_sup_obj(p_auto_install_sup_obj => true)"
  else
    echo "NOTE: apex/$APP has supporting-object scripts; they will NOT run (add -supporting-objects to run them)."
  fi
elif [[ $SUPOBJ -eq 1 ]]; then
  echo "NOTE: -supporting-objects given, but apex/$APP has no supporting-objects folder - nothing to run."
fi

# NOTE: `apex` is a SQLcl command, not SQL - `whenever sqlerror` does NOT
# catch its failures. Success is judged from the actual output, and the
# workspace is passed explicitly: on a schema granted to multiple
# workspaces, an import without -workspace bails silently.
echo "== importing (output streams as SQLcl produces it) =="
OUT="$(sql -name "$CONN" <<SQLEOF | tee /dev/stderr
set define off
$SUPOBJ_SQL
apex import -input $REPO/apex/$APP -workspace $WS
exit
SQLEOF
)"
if grep -qi "import successful" <<< "$OUT"; then
  # target now equals the repo, so today becomes the new drift baseline
  date +%F > "$PULLSTAMP"
  # the server validated the WHOLE app to accept it: this tree is the new
  # baseline, so the next push only checks pages edited after this one
  mkdir -p "$REPO/tmp"
  tree_hash > "$REPO/tmp/.validated-$APP"
  manifest  > "$REPO/tmp/.validated-$APP.files"
  echo "Imported. Smoke-test in the browser, then pull.sh + commit."
  if [[ -n "$SUPOBJ_SQL" ]]; then
    echo "Supporting-object scripts ran. Failures are SILENT: check their data with a query now."
  fi
  echo "NOTE: the import disabled any scheduled jobs in the target app."
  echo "      Dev apps: usually fine. PRODUCTION promote: run the manual"
  echo "      re-enable scripts - see scripts/prod-promote/README.md"
else
  echo "IMPORT DID NOT SUCCEED - read the output above. Nothing was replaced." >&2
  exit 1
fi
