#!/usr/bin/env bash
# HUMAN-ONLY. Promote a working copy to the MAIN app by replace.
# Usage: promote.sh [-supporting-objects] MAIN_APP_ID [SRC_APP_DIR] [CONN] [WORKSPACE]
#   MAIN_APP_ID  the app to REPLACE (e.g. 102) - required, never defaulted
#   SRC_APP_DIR  dir under apex/ holding the working copy's export
#                (default: the stamped app, normally the working copy)
#   -supporting-objects
#                also run the source's supporting-object scripts in the
#                import session. Off by default; listed in the PROMOTE banner
#                that you confirm. See docs/apexlang-notes.md, "Supporting
#                objects".
#
# This REPLACES the main application with the working copy's source.
# Procedure (docs/apexlang-notes.md, "Promoting a working copy to
# production by replace"), enforced in order:
#   1. target sanity  - exists, is not itself a working copy, is not the source
#   2. validate       - source must validate (cache-skip if tree unchanged)
#   3. backup         - MANDATORY split export of the current main app
#   4. confirmation   - you type the main app id; anything else aborts
#   5. import         - with -id/-name/-alias of MAIN, so production keeps
#                       its own name, alias and f?p=ALIAS: links
#   6. reminders      - scheduled jobs come out disabled; WC must be recut
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"

SUPOBJ=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -supporting-objects) SUPOBJ=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
TARGET="${1:?usage: promote.sh [-supporting-objects] MAIN_APP_ID [SRC_APP_DIR] [CONN] [WORKSPACE]}"
APP="${2:-__APP__}"
CONN="${3:-__CONN__}"
WS="${4:-__WORKSPACE__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/apex/$APP"

[[ "$TARGET" =~ ^[0-9]+$ ]] || { echo "MAIN_APP_ID must be a number" >&2; exit 1; }
[[ -d "$SRC" ]] || { echo "no such app dir: apex/$APP" >&2; exit 1; }
SRC_ID="$(grep -ohP '"id"\s*:\s*\K[0-9]+' "$SRC"/deployments/*.json 2>/dev/null | head -1 || true)"
[[ "$SRC_ID" != "$TARGET" ]] || {
  echo "apex/$APP IS app $TARGET - that's a normal push, not a promote. Use push.sh." >&2; exit 1; }

# ---- 1. target sanity --------------------------------------------------------
echo "== looking up main app $TARGET =="
META="$(sql -S -name "$CONN" <<SQLEOF
set heading off feedback off pagesize 0 linesize 4000 define off
select 'META|' || application_name || '|' || alias || '|' ||
       to_char(last_updated_on, 'YYYY-MM-DD HH24:MI') || '|' || last_updated_by || '|' || pages
from   apex_applications
where  application_id = $TARGET;
exit
SQLEOF
)"
LINE="$(grep '^META|' <<< "$META" || true)"
[[ -n "$LINE" ]] || { echo "app $TARGET not found in this workspace - wrong id or connection" >&2; exit 1; }
IFS='|' read -r _ T_NAME T_ALIAS T_UPD T_BY T_PAGES <<< "$LINE"
if [[ "$T_NAME" == *"(Working Copy:"* ]]; then
  echo "app $TARGET is itself a working copy ('$T_NAME'). Promote targets the MAIN app only." >&2
  exit 1
fi

# ---- 2. validate the source ----------------------------------------------------
tree_hash() { find "$SRC" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1; }
STAMP="$REPO/tmp/.validated-$APP"
if [[ -f "$STAMP" ]] && [[ "$(cat "$STAMP")" == "$(tree_hash)" ]]; then
  echo "source unchanged since last successful validation - skipping validate"
else
  echo "== validating apex/$APP before promote =="
  "$REPO/scripts/apex-validate.sh" "$APP" || { echo "validation failed - not promoting" >&2; exit 1; }
fi

# ---- 3. mandatory backup of the current main app --------------------------------
BK="$REPO/tmp/backup-promote-$TARGET-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
echo "== backing up main app $TARGET to $BK (rollback artifact) =="
sql -name "$CONN" <<SQLEOF
set define off
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $TARGET -dir "$BK" -split -skipExportDate
exit success
SQLEOF
[[ -f "$BK/f$TARGET/install.sql" ]] || { echo "backup export incomplete - NOT promoting" >&2; exit 1; }
if [[ -d "$BK/f$TARGET/supporting_objects" || -d "$BK/f$TARGET/application/supporting_objects" ]]; then
  echo "NOTE: main app $TARGET has supporting objects - check the working copy carries them too."
fi

# supporting-object scripts: opt-in, shown in the banner below, run in the
# import session (`apex import` never runs them by itself)
SO="$SRC/supporting-objects"
SUPOBJ_SQL=""; SO_LINE="not run (add -supporting-objects to run them)"
if [[ -d "$SO" && $SUPOBJ -eq 1 ]]; then
  SUPOBJ_SQL="exec apex_application_install.set_auto_install_sup_obj(p_auto_install_sup_obj => true)"
  SO_LINE="WILL RUN in the app's schema:"
  for f in "$SO"/install-scripts/*.sql "$SO"/upgrade-scripts/*.sql; do
    [[ -f "$f" ]] && SO_LINE+=$'\n'"          ${f#"$SO"/}"
  done
  grep -q "upgradeWhenSqlQuery" "$SO/supporting-objects.apx" 2>/dev/null \
    && SO_LINE+=$'\n'"          (upgrade query set: if it returns a row, UPGRADE scripts run instead)"
  SO_LINE+=$'\n'"          failures are SILENT - check their data after the promote"
elif [[ $SUPOBJ -eq 1 ]]; then
  SO_LINE="none - apex/$APP has no supporting-objects folder"
elif [[ ! -d "$SO" ]]; then
  SO_LINE="none in apex/$APP"
fi

# ---- 4. typed confirmation -----------------------------------------------------
cat <<EOF

================================ PROMOTE =================================
 REPLACE  main app $TARGET  "$T_NAME"  (alias: ${T_ALIAS:-none})
          $T_PAGES pages, last changed $T_UPD by $T_BY
 WITH     apex/$APP  (working copy app ${SRC_ID:-?})
 KEEPS    main's id, name and alias
 SCRIPTS  supporting objects: $SO_LINE
 BACKUP   $BK
 AFTER    every automation / REST sync in app $TARGET is DISABLED
          until you run scripts/prod-promote/*.sql
 CHECK    nobody changed app $TARGET since this working copy was cut
          (last change above) - their work would be erased.
==========================================================================
EOF
echo -n "Type the main app id ($TARGET) to confirm: "
read -r CONFIRM
[[ "$CONFIRM" == "$TARGET" ]] || { echo "confirmation did not match - promote aborted, nothing changed." >&2; exit 1; }

# ---- 5. import over main, keeping main's identity -------------------------------
ALIAS_ARG=""; [[ -n "$T_ALIAS" ]] && ALIAS_ARG="-alias $T_ALIAS"
echo "== promoting: importing apex/$APP over app $TARGET =="
OUT="$(sql -name "$CONN" <<SQLEOF | tee /dev/stderr
set define off
$SUPOBJ_SQL
apex import -input $SRC -id $TARGET -name "$T_NAME" $ALIAS_ARG -workspace $WS
exit
SQLEOF
)"
if ! grep -qi "import successful" <<< "$OUT"; then
  echo "PROMOTE DID NOT SUCCEED - read the output above." >&2
  echo "If the import started, app $TARGET may be partly replaced: restore from $BK" >&2
  echo "(sql -name $CONN, then @$BK/f$TARGET/install.sql with the same workspace)." >&2
  exit 1
fi

# ---- 6. what's left to do ------------------------------------------------------
cat <<EOF

PROMOTED: app $TARGET now runs apex/$APP.  Remaining steps (manual, on purpose):
  1. Re-enable scheduled jobs:  scripts/prod-promote/*.sql  (see its README),
     then confirm one automation actually fires.
  2. Smoke-test app $TARGET in the browser.$( [[ -n "$SUPOBJ_SQL" ]] && printf '\n     Supporting-object scripts ran: check their data with a query (failures are silent).' || true )
  3. Retire the promoted working copy and cut a fresh one from app $TARGET;
     the new copy has a NEW app id - retarget deployments/*.json and the
     app dir (see docs/apexlang-notes.md).
  Rollback artifact: $BK
EOF
