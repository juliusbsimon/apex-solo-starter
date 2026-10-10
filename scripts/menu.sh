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
  2) Validate    only what changed since the last good tree (v = whole tree)
  3) Push        repo -> Builder (drift check + validate + import)
  4) Push+Backup same, with a full export of the current app first
  s) Push+SupObj same, and run the app's supporting-object scripts
                 (lists them and asks first; a plain push never runs them)
  5) Migrate     run db/migrations file(s), then refresh RO grants
  6) Git status + diff summary
  7) Commit & push to git (prompts for a message)
  8) Refresh RO grants (promptless, needs admin conn)
  9) PROMOTE working copy over the main app (backup + typed confirm)
  q) Quit
MENU
  read -rp "> " choice
  case "$choice" in
    1) run scripts/pull.sh ;;
    2) run scripts/apex-validate.sh -changed ;;
    v|V) run scripts/apex-validate.sh ;;
    3) run scripts/push.sh ;;
    4) run scripts/push.sh -backup ;;
    s|S) run scripts/push.sh -supporting-objects ;;
    5)
      ls -1 db/migrations/*.sql 2>/dev/null | grep -v README || echo "(no migration files)"
      read -rp "File(s), space-separated (globs ok, run order = name order): " -a files
      [[ ${#files[@]} -gt 0 ]] || { echo "nothing chosen"; continue; }
      read -rp "Admin connection for the grants refresh (Enter to skip): " admin
      if [[ -n "$admin" ]]; then run scripts/migrate.sh "${files[@]}" "$admin"
      else run scripts/migrate.sh "${files[@]}"; fi
      ;;
    6) run git status; run git diff --stat ;;
    9)
      read -rp "Main app id to REPLACE (e.g. 102): " target
      [[ "$target" =~ ^[0-9]+$ ]] || { echo "aborted"; continue; }
      read -rp "Also run the working copy's supporting-object scripts? [y/N] " so
      if [[ "$so" == y* || "$so" == Y* ]]; then run scripts/promote.sh -supporting-objects "$target"
      else run scripts/promote.sh "$target"; fi
      ;;
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
