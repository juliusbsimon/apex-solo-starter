#!/usr/bin/env bash
# Lists database source files that changed but that NO pending migration
# deploys. Read-only: git and grep, no database. Safe for the agent to run.
#
# Rule (CLAUDE.md iron rule 5): everything the database needs ships in a
# migration file. A new or changed db/*.sql source (procedure, package,
# trigger, view...) is deployed by a migration that includes it
# (`@@../p_x.sql`) or carries its code inline. This script catches the
# source file that was written and never wired into a migration.
#
#   "changed"  = untracked or modified now, or changed in a commit since the
#                ledger (db/migrations/applied-<CONN>.txt) was last committed
#   "covered"  = its file name appears in a migration NOT yet in the ledger
#
# Usage: db-coverage.sh [CONN]     exit 0 = all covered, 1 = something isn't
set -uo pipefail
CONN="${1:-__CONN__}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 0
LEDGER="db/migrations/applied-$CONN.txt"
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# db sources that are not migrations and not the RO-account scripts
is_source() {
  [[ "$1" == db/*.sql || "$1" == db/*/*.sql || "$1" == db/*/*/*.sql ]] || return 1
  [[ "$1" == db/migrations/* ]] && return 1
  case "$(basename "$1")" in create-claude-ro.sql|refresh-claude-ro-grants.sql) return 1 ;; esac
  return 0
}

BASE="$(git log -1 --format=%H -- "$LEDGER" 2>/dev/null)"
{
  git status --porcelain -uall -- db 2>/dev/null | cut -c4- | sed 's/.* -> //'
  [[ -n "$BASE" ]] && git diff --name-only "$BASE" HEAD -- db 2>/dev/null
} | sort -u > "${TMPDIR:-/tmp}/.dbcov.$$"

# migrations still to run (not in the ledger)
PENDING=()
for m in db/migrations/*.sql; do
  [[ -f "$m" ]] || continue
  grep -qxF "$(basename "$m")" "$LEDGER" 2>/dev/null || PENDING+=("$m")
done

missing=0
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  is_source "$f" || continue
  b="$(basename "$f")"
  if [[ ${#PENDING[@]} -eq 0 ]] || ! grep -qF "$b" "${PENDING[@]}" 2>/dev/null; then
    [[ $missing -eq 0 ]] && echo "NOT DEPLOYED BY ANY PENDING MIGRATION (changed db sources):"
    echo "   $f      -> add to a migration:  @@../${f#db/}"
    missing=1
  fi
done < "${TMPDIR:-/tmp}/.dbcov.$$"
rm -f "${TMPDIR:-/tmp}/.dbcov.$$"
[[ $missing -eq 1 ]] && echo "   (or carry the code inline in the migration) - otherwise it never reaches the database."
exit $missing
