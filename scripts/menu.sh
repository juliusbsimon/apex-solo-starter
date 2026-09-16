#!/usr/bin/env bash
# HUMAN-ONLY menu over the workflow scripts. No logic of its own: every
# choice runs the same script you would type, in this terminal, so all
# prompts (drift check, passwords) work exactly as documented.
# Run from anywhere inside the project:  bash scripts/menu.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

run() { echo; echo ">> $*"; echo; "$@" || echo "-- exited with an error (read above) --"; echo; }

while true; do
  cat <<MENU
=========== $(basename "$REPO") ===========
  1) Pull        Builder -> repo (do this before editing)
  2) Validate    check the APEXlang tree
  3) Push        repo -> Builder (drift check + validate + import)
  4) Push+Backup same, with a full export of the current app first
  5) Migrate     run db/migrations file(s), then refresh RO grants
  6) Git status + diff summary
  7) Commit & push to git (prompts for a message)
  8) Refresh RO grants (promptless, needs admin conn)
  q) Quit
MENU
  read -rp "> " choice
  case "$choice" in
    1) run scripts/pull.sh ;;
    2) run scripts/apex-validate.sh ;;
    3) run scripts/push.sh ;;
    4) run scripts/push.sh -backup ;;
    5)
      ls -1 db/migrations/*.sql 2>/dev/null | grep -v README || echo "(no migration files)"
      read -rp "File(s), space-separated (globs ok, run order = name order): " -a files
      [[ ${#files[@]} -gt 0 ]] || { echo "nothing chosen"; continue; }
      read -rp "Admin connection for the grants refresh (Enter to skip): " admin
      if [[ -n "$admin" ]]; then run scripts/migrate.sh "${files[@]}" "$admin"
      else run scripts/migrate.sh "${files[@]}"; fi
      ;;
    6) run git status; run git diff --stat ;;
    8)
      read -rp "Admin connection: " admin
      [[ -n "$admin" ]] || { echo "aborted"; continue; }
      run scripts/refresh-ro-grants.sh "$admin"
      ;;
    7)
      git status --short
      read -rp "Commit message (Enter aborts): " msg
      [[ -n "$msg" ]] || { echo "aborted"; continue; }
      run git add -A
      run git commit -m "$msg"
      run git push
      ;;
    q|Q) exit 0 ;;
    *) echo "?" ;;
  esac
done
