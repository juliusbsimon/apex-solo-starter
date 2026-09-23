#!/usr/bin/env bash
# Update an existing project to the latest apex-solo-starter. SAFE TO RE-RUN:
# this script never contains literal placeholder tokens (they are built at
# runtime), so it cannot stamp itself into a corrupted single-use state.
#
# Run FROM THE PROJECT ROOT:
#   bash scripts/update-from-template.sh
# or bootstrap on an old project:
#   git clone --depth 1 https://github.com/juliusbsimon/apex-solo-starter.git /tmp/starter
#   bash /tmp/starter/scripts/update-from-template.sh
#
# File policy:
#   OVERWRITTEN (template-owned): scripts/*.sh|*.ps1 (this script's own
#     local copy is replaced too, but LAST and via mv — see end of file),
#     .claude/settings.json, db/create-claude-ro.sql,
#     db/refresh-claude-ro-grants.sql, db/migrations/README.md,
#     RUNBOOK.md, GETTING-STARTED.md
#   ADDED IF MISSING: scripts/prod-promote/*, templates/README.md,
#     docs/apexlang-notes.md, CLAUDE.md
#   NEVER CLOBBERED: existing CLAUDE.md / notes / prod-promote scripts -
#     template versions land beside them as *.template.new ONLY when they
#     genuinely differ after stamping.
set -euo pipefail
[[ -d .git && -d apex ]] || { echo "run from the project root" >&2; exit 1; }
SELF="update-from-template.sh"

STARTER="${STARTER:-/tmp/starter}"
if [[ ! -d "$STARTER/scripts" ]]; then
  git clone --depth 1 https://github.com/juliusbsimon/apex-solo-starter.git "$STARTER"
fi

# ---- placeholder tokens built at runtime so this file never contains them
T="__"
tAPP="${T}APP${T}"; tTITLE="${T}APP_TITLE${T}"; tID="${T}APP_ID${T}"
tWS="${T}WORKSPACE${T}"; tSCHEMA="${T}SCHEMA${T}"; tCONN="${T}CONN${T}"

# ---- detect stamped values from the existing project, prompt for the rest
# prefer an already-stamped default app (pull.sh) over alphabetical order
APP_D="$(grep -oP 'APP="\$\{3:-\K[^}"]*' scripts/pull.sh 2>/dev/null | head -1 || true)"
[[ -n "$APP_D" && -d "apex/$APP_D" ]] || APP_D="$(ls apex | head -1)"
CONN_D="$(grep -oP 'CONN="\$\{1:-\K[^}"]*' scripts/pull.sh 2>/dev/null | head -1 || true)"
# TWO DIFFERENT NAMES - never conflate them:
#   RO_CONN_D = the SAVED SQLCL CONNECTION name (ro.sh default; local, case-sensitive)
#   RO_USER_D = the DATABASE USERNAME the grant scripts target (:ro_user)
# They match only by convention; a project may have saved the connection
# under a different name than the account. Each is preserved separately.
RO_CONN_D="$(grep -oP 'CONN="\$\{2:-\K[^}"]*' scripts/ro.sh 2>/dev/null | head -1 || true)"
RO_USER_D="$(grep -ohP "ro_user\s*:=\s*upper\('\K[^']+" db/refresh-claude-ro-grants.sql db/create-claude-ro.sql 2>/dev/null | head -1 || true)"
if [[ "$(ls apex | wc -l)" -gt 1 ]]; then
  echo "This repo holds several apps under apex/:  $(ls apex | tr '\n' ' ')"
  echo "The one you name here is only the NO-ARGUMENT DEFAULT - the others"
  echo "stay reachable through the GUI's app selector and script arguments."
fi
read -rp "Default app dir name [${APP_D}]: " APP; APP="${APP:-$APP_D}"
[[ -d "apex/$APP" ]] || { echo "no such dir: apex/$APP" >&2; exit 1; }
# app id comes from the CHOSEN app's deployments, not whichever globs first
APPID_D="$(grep -oP '"id"\s*:\s*\K[0-9]+' "apex/$APP"/deployments/*.json 2>/dev/null | head -1 || true)"
read -rp "SQLcl connection name (CASE-SENSITIVE) [${CONN_D}]: " CONN; CONN="${CONN:-$CONN_D}"
read -rp "DEV application id of $APP [${APPID_D}]: " APP_ID; APP_ID="${APP_ID:-$APPID_D}"
read -rp "APEX workspace name: " WS
read -rp "Parsing schema [${WS}]: " SCHEMA; SCHEMA="${SCHEMA:-$WS}"
[[ -n "$APP" && -n "$CONN" && -n "$APP_ID" && -n "$WS" ]] || { echo "missing values" >&2; exit 1; }

stamp() {
  sed -i "s|$tTITLE|$APP|g; s|$tID|$APP_ID|g; s|$tWS|$WS|g; s|$tSCHEMA|$SCHEMA|g; s|$tCONN|$CONN|g; s|$tAPP|$APP|g" "$@"
}

# ---- template-owned: overwrite. SELF IS NOT IN THIS LOOP: bash reads a
# script lazily while running it, so cp-ing new content over this file would
# make bash resume at the old byte offset inside new text and abort with a
# syntax error, leaving everything after the cp (the stamping!) not run.
# Self is replaced at the very END of this script, atomically, via mv.
mkdir -p scripts db/migrations .claude docs templates
STAMP_LIST=()
for f in pull.sh push.sh apex-validate.sh ro.sh migrate.sh setup-prereqs.sh \
         menu.sh gui.py refresh-ro-grants.sh refresh-ro-grants.ps1 \
         pull.ps1 push.ps1 apex-validate.ps1 ro.ps1 migrate.ps1 check-prereqs.ps1; do
  [[ -f "$STARTER/scripts/$f" ]] || continue
  cp "$STARTER/scripts/$f" "scripts/$f"
  STAMP_LIST+=("scripts/$f")
done
cp "$STARTER/.claude/settings.json" .claude/
cp "$STARTER/db/create-claude-ro.sql" db/
if [[ -f "$STARTER/db/refresh-claude-ro-grants.sql" ]]; then
  cp "$STARTER/db/refresh-claude-ro-grants.sql" db/
fi
cp "$STARTER/db/migrations/README.md" db/migrations/
cp "$STARTER/RUNBOOK.md" "$STARTER/GETTING-STARTED.md" .
STAMP_LIST+=(db/create-claude-ro.sql RUNBOOK.md)
if [[ -f db/refresh-claude-ro-grants.sql ]]; then
  STAMP_LIST+=(db/refresh-claude-ro-grants.sql)
fi
stamp "${STAMP_LIST[@]}"
# preserve existing names if they differ from the fresh <SCHEMA>_CLAUDE_RO
# stamp - connection name into the ro wrappers ONLY, DB username into the
# grant scripts ONLY (renaming either is a manual act, not the updater's)
RO_CONN="${SCHEMA}_CLAUDE_RO"; RO_USER="${SCHEMA}_CLAUDE_RO"
if [[ -n "$RO_CONN_D" && "$RO_CONN_D" != "$RO_CONN" ]]; then
  sed -i "s|${SCHEMA}_CLAUDE_RO|$RO_CONN_D|g" scripts/ro.sh scripts/ro.ps1
  echo "  (kept existing RO saved-connection name: $RO_CONN_D)"
  RO_CONN="$RO_CONN_D"
fi
if [[ -n "$RO_USER_D" && "$RO_USER_D" != "$RO_USER" ]]; then
  sed -i "s|upper('${SCHEMA}_CLAUDE_RO')|upper('$RO_USER_D')|g" \
    db/create-claude-ro.sql db/refresh-claude-ro-grants.sql
  echo "  (kept existing RO database username: $RO_USER_D)"
  RO_USER="$RO_USER_D"
fi
chmod +x scripts/*.sh

# ---- add-if-missing; side-copy ONLY on a real post-stamp difference
side() { # $1 template-src  $2 project-dest
  local tmp; tmp="$(mktemp)"
  cp "$1" "$tmp"; stamp "$tmp" 2>/dev/null || true
  if [[ ! -e "$2" ]]; then
    mv "$tmp" "$2"
  elif ! cmp -s "$tmp" "$2"; then
    mv "$tmp" "$2.template.new"
    echo "  MERGE BY HAND: $2.template.new (yours kept in place)"
  else
    rm -f "$tmp"
  fi
}
mkdir -p scripts/prod-promote
side "$STARTER/scripts/prod-promote/README.md" scripts/prod-promote/README.md
side "$STARTER/scripts/prod-promote/10-enable-automations.sql" scripts/prod-promote/10-enable-automations.sql
side "$STARTER/scripts/prod-promote/20-enable-rest-sync.sql" scripts/prod-promote/20-enable-rest-sync.sql
side "$STARTER/templates/README.md" templates/README.md
side "$STARTER/docs/apexlang-notes.md" docs/apexlang-notes.md
side "$STARTER/CLAUDE.md" CLAUDE.md

# ---- verify (tokens built at runtime; self excluded from the sweep)
if grep -rn "$tAPP\|$tCONN\|$tWS\|$tSCHEMA\|$tID" scripts db RUNBOOK.md 2>/dev/null \
     | grep -v "$SELF"; then
  echo "STOP: unstamped placeholders above" >&2; exit 1
fi
echo
echo "Updated. Manual follow-ups:"
echo "  1. Merge any *.template.new files listed above, then delete them."
echo "  2. RO saved connection: ro.sh expects '$RO_CONN' (case-sensitive;"
echo "     connmgr list shows what exists). Grant scripts target DB user"
echo "     '$(echo "$RO_USER" | tr a-z A-Z)' (dba_users shows what exists)."
echo "  3. Review: git diff   then commit:"
echo "     git add -A && git commit -m 'chore: update scripts from template' && git push"

# ---- LAST LINES ON PURPOSE: replace this script itself. mv swaps in a new
# inode, so the bash that is still reading THIS file keeps its old bytes and
# finishes cleanly; a cp here (or earlier) would corrupt the running parse.
TMPSELF="$(mktemp "scripts/.$SELF.XXXXXX")"
cp "$STARTER/scripts/$SELF" "$TMPSELF"
chmod +x "$TMPSELF"
mv -f "$TMPSELF" "scripts/$SELF"
