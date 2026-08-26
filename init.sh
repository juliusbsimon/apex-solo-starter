#!/usr/bin/env bash
# One-time project setup (Linux/WSL). Unzip into an empty folder, then: ./init.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

read -rp "Short app name, lowercase, no spaces (e.g. portal): " APP
read -rp "App title (e.g. ACME - Order Tracking): " APP_TITLE
read -rp "DEV application id (e.g. 139): " APP_ID
read -rp "APEX workspace name (e.g. ACME): " WS
read -rp "Parsing schema [default: $WS] (workspace and schema often differ!): " SCHEMA
SCHEMA="${SCHEMA:-$WS}"
read -rp "SQLcl connection name to create/use (e.g. ${APP^^}_DEV): " CONN

[[ "$APP_ID" =~ ^[0-9]+$ ]] || { echo "application id must be a number" >&2; exit 1; }

find . -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.md" -o -name "*.sql" -o -name "*.json" \) \
    ! -name "init.sh" ! -name "init.ps1" -print0 |
  xargs -0 sed -i \
    -e "s|__APP_TITLE__|$APP_TITLE|g" \
    -e "s|__APP_ID__|$APP_ID|g" \
    -e "s|__WORKSPACE__|$WS|g" \
    -e "s|__SCHEMA__|$SCHEMA|g" \
    -e "s|__CONN__|$CONN|g" \
    -e "s|__APP__|$APP|g"

mkdir -p "apex/$APP"; rm -f apex/.gitkeep
[[ -d .git ]] || git init -b main >/dev/null

cat <<STEPS

Stamped. Remaining steps (connection names are CASE-SENSITIVE - save them
exactly as printed below; the scripts use these spellings verbatim):
  1. Save the connection (parsing schema of workspace $WS) — note: SQLcl's
     connection store is per-OS-user, so save it inside WSL even if a Windows
     copy exists:
       sql /nolog
       connect -save $CONN -savepwd schema/<password>@//host:1521/service
  2. (Optional, recommended) agent read-only account:
       run db/create-claude-ro.sql as an admin user - schema is already
       stamped and it prompts for a password, nothing to edit - then:
       connect -save ${APP}_CLAUDE_RO -savepwd ${APP}_claude_ro/<pw>@//host:1521/service
  3. Baseline:  ./scripts/pull.sh   then review, and:
       git add -A && git commit -m "chore: baseline APEXlang export of $APP"
  4. Remote:    git remote add origin <url> && git push -u origin main
  5. Determinism check: pull.sh again -> git status must be clean.
  6. Validate the baseline: ./scripts/apex-validate.sh - long-lived apps
     often export with Builder-side errors; fix them before relying on push.

This checklist also lives in RUNBOOK.md SS2 "Setup at a glance".
Then read RUNBOOK.md — the daily loop (§3) and guardrails (§3b).
You can delete init.sh and init.ps1 now (keep whichever OS's scripts you use).
STEPS
