#!/usr/bin/env bash
# Update an existing project to the latest apex-solo-starter.
# Run FROM THE PROJECT ROOT:
#   bash scripts/update-from-template.sh        (if you already have this script)
# or bootstrap it on an old project:
#   git clone --depth 1 https://github.com/juliusbsimon/apex-solo-starter.git /tmp/starter
#   bash /tmp/starter/scripts/update-from-template.sh
#
# File policy:
#   OVERWRITTEN (template-owned): scripts/*.sh|*.ps1, .claude/settings.json,
#     db/create-claude-ro.sql, db/migrations/README.md, RUNBOOK.md,
#     GETTING-STARTED.md
#   ADDED IF MISSING: scripts/prod-promote/*, templates/README.md,
#     docs/apexlang-notes.md
#   NEVER TOUCHED: your apex/, db/ content, deployments, CLAUDE.md and
#     existing notes/prod-promote (template versions land as *.template.new
#     beside them for hand-merging - they may carry your local additions)
set -euo pipefail
[[ -d .git && -d apex ]] || { echo "run from the project root" >&2; exit 1; }

STARTER="${STARTER:-/tmp/starter}"
if [[ ! -d "$STARTER/scripts" ]]; then
  git clone --depth 1 https://github.com/juliusbsimon/apex-solo-starter.git "$STARTER"
fi

# ---- detect stamped values from the existing project, prompt for the rest
detect() { grep -oP "$2" "$1" 2>/dev/null | head -1 || true; }
APP_D="$(ls apex | head -1)"
CONN_D="$(detect scripts/pull.sh 'CONN="\$\{1:-\K[^}"]*')"
APPID_D="$(grep -oP '"id"\s*:\s*\K[0-9]+' apex/*/deployments/default.json 2>/dev/null | head -1 || true)"
read -rp "App dir name [${APP_D}]: " APP; APP="${APP:-$APP_D}"
read -rp "SQLcl connection name (CASE-SENSITIVE) [${CONN_D}]: " CONN; CONN="${CONN:-$CONN_D}"
read -rp "DEV application id [${APPID_D}]: " APP_ID; APP_ID="${APP_ID:-$APPID_D}"
read -rp "APEX workspace name: " WS
read -rp "Parsing schema [${WS}]: " SCHEMA; SCHEMA="${SCHEMA:-$WS}"
[[ -n "$APP" && -n "$CONN" && -n "$APP_ID" && -n "$WS" ]] || { echo "missing values" >&2; exit 1; }

stamp() {
  sed -i "s|__APP_TITLE__|$APP|g; s|__APP_ID__|$APP_ID|g; s|__WORKSPACE__|$WS|g; s|__SCHEMA__|$SCHEMA|g; s|__CONN__|$CONN|g; s|__APP__|$APP|g" "$@"
}

# ---- template-owned: overwrite
mkdir -p scripts db/migrations .claude docs templates
for f in pull.sh push.sh apex-validate.sh ro.sh migrate.sh setup-prereqs.sh \
         pull.ps1 push.ps1 apex-validate.ps1 ro.ps1 migrate.ps1 check-prereqs.ps1; do
  [[ -f "$STARTER/scripts/$f" ]] && cp "$STARTER/scripts/$f" scripts/
done
cp "$STARTER/.claude/settings.json" .claude/
cp "$STARTER/db/create-claude-ro.sql" db/
cp "$STARTER/db/migrations/README.md" db/migrations/
cp "$STARTER/RUNBOOK.md" "$STARTER/GETTING-STARTED.md" .
stamp scripts/*.sh scripts/*.ps1 db/create-claude-ro.sql RUNBOOK.md
chmod +x scripts/*.sh

# ---- add-if-missing / side-copy-if-present
side() { # $1 src  $2 dest
  if [[ -e "$2" ]]; then
    if ! cmp -s "$1" "$2"; then cp "$1" "$2.template.new"; stamp "$2.template.new" 2>/dev/null || true
      echo "  MERGE BY HAND: $2.template.new (yours kept in place)"; fi
  else cp "$1" "$2"; stamp "$2" 2>/dev/null || true; fi
}
mkdir -p scripts/prod-promote
side "$STARTER/scripts/prod-promote/README.md" scripts/prod-promote/README.md
side "$STARTER/scripts/prod-promote/10-enable-automations.sql" scripts/prod-promote/10-enable-automations.sql
side "$STARTER/scripts/prod-promote/20-enable-rest-sync.sql" scripts/prod-promote/20-enable-rest-sync.sql
side "$STARTER/templates/README.md" templates/README.md
side "$STARTER/docs/apexlang-notes.md" docs/apexlang-notes.md
side "$STARTER/CLAUDE.md" CLAUDE.md

# ---- verify
if grep -rn "__APP__\|__CONN__\|__WORKSPACE__\|__SCHEMA__\|__APP_ID__" scripts db RUNBOOK.md 2>/dev/null; then
  echo "STOP: unstamped placeholders above" >&2; exit 1
fi
echo
echo "Updated. Manual follow-ups:"
echo "  1. Merge any *.template.new files listed above, then delete them."
echo "  2. RO connection: scripts now expect '${APP}_CLAUDE_RO' (case-sensitive)."
echo "     Create/re-save it if yours differs: connmgr list shows what exists."
echo "  3. Review: git diff   then commit:"
echo "     git add -A && git commit -m 'chore: update scripts from template' && git push"
