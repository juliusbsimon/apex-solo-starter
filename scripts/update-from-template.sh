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
#   OVERWRITTEN (template-owned): scripts/*.sh|*.ps1 (except this script's
#     local copy, replaced from the template like the rest),
#     .claude/settings.json, db/create-claude-ro.sql, db/migrations/README.md,
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
APP_D="$(ls apex | head -1)"
CONN_D="$(grep -oP 'CONN="\$\{1:-\K[^}"]*' scripts/pull.sh 2>/dev/null | head -1 || true)"
APPID_D="$(grep -oP '"id"\s*:\s*\K[0-9]+' apex/*/deployments/default.json 2>/dev/null | head -1 || true)"
read -rp "App dir name [${APP_D}]: " APP; APP="${APP:-$APP_D}"
read -rp "SQLcl connection name (CASE-SENSITIVE) [${CONN_D}]: " CONN; CONN="${CONN:-$CONN_D}"
read -rp "DEV application id [${APPID_D}]: " APP_ID; APP_ID="${APP_ID:-$APPID_D}"
read -rp "APEX workspace name: " WS
read -rp "Parsing schema [${WS}]: " SCHEMA; SCHEMA="${SCHEMA:-$WS}"
[[ -n "$APP" && -n "$CONN" && -n "$APP_ID" && -n "$WS" ]] || { echo "missing values" >&2; exit 1; }

stamp() {
  sed -i "s|$tTITLE|$APP|g; s|$tID|$APP_ID|g; s|$tWS|$WS|g; s|$tSCHEMA|$SCHEMA|g; s|$tCONN|$CONN|g; s|$tAPP|$APP|g" "$@"
}

# ---- template-owned: overwrite (self excluded from stamping as second belt)
mkdir -p scripts db/migrations .claude docs templates
STAMP_LIST=()
for f in pull.sh push.sh apex-validate.sh ro.sh migrate.sh setup-prereqs.sh \
         pull.ps1 push.ps1 apex-validate.ps1 ro.ps1 migrate.ps1 check-prereqs.ps1 "$SELF"; do
  [[ -f "$STARTER/scripts/$f" ]] || continue
  cp "$STARTER/scripts/$f" "scripts/$f"
  [[ "$f" == "$SELF" ]] || STAMP_LIST+=("scripts/$f")
done
cp "$STARTER/.claude/settings.json" .claude/
cp "$STARTER/db/create-claude-ro.sql" db/
cp "$STARTER/db/migrations/README.md" db/migrations/
cp "$STARTER/RUNBOOK.md" "$STARTER/GETTING-STARTED.md" .
STAMP_LIST+=(db/create-claude-ro.sql RUNBOOK.md)
stamp "${STAMP_LIST[@]}"
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
echo "  2. RO connection: scripts expect '${APP}_CLAUDE_RO' (case-sensitive)."
echo "     connmgr list shows what exists; re-save if yours differs."
echo "  3. Review: git diff   then commit:"
echo "     git add -A && git commit -m 'chore: update scripts from template' && git push"
