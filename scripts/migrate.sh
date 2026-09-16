#!/usr/bin/env bash
# HUMAN-ONLY. Runs one or more migrations in order, then refreshes the
# CLAUDE_RO account's grants ONCE at the end (promptless) so the agent can
# see any new tables — the step everyone forgets.
# Usage: migrate.sh <file.sql> [<file.sql> ...] [ADMIN_CONN]
#   Every argument that names an existing file is a migration to run.
#   A final argument that is NOT a file is taken as the admin connection
#   name for the grants refresh. Migrations stop at the first failure;
#   the refresh runs only if every migration succeeded.
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
CONN="__CONN__"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ $# -ge 1 ]] || { echo "usage: migrate.sh <file.sql> [<file.sql> ...] [ADMIN_CONN]" >&2; exit 1; }

# sort arguments: existing files are migrations; a trailing non-file is ADMIN
FILES=()
ADMIN=""
ARGS=("$@")
LAST=$(( ${#ARGS[@]} - 1 ))
for i in "${!ARGS[@]}"; do
  a="${ARGS[$i]}"
  if [[ -f "$a" ]]; then
    FILES+=("$a")
  elif [[ $i -eq $LAST ]]; then
    ADMIN="$a"
  else
    echo "no such file: $a" >&2; exit 1
  fi
done
[[ ${#FILES[@]} -ge 1 ]] || { echo "no migration files given" >&2; exit 1; }

n=0
for FILE in "${FILES[@]}"; do
  n=$((n+1))
  echo "== [$n/${#FILES[@]}] running $FILE as $CONN =="
  sql -name "$CONN" <<SQLEOF
set define off
whenever sqlerror exit failure
@$FILE
exit success
SQLEOF
done

echo "== refreshing read-only-account grants (no prompt) =="
if [[ -n "$ADMIN" ]]; then
  sql -name "$ADMIN" @"$REPO/db/refresh-claude-ro-grants.sql"
else
  echo "NOTE: no admin connection given - run scripts/refresh-ro-grants.sh"
  echo "      ADMIN_CONN (or the GUI's 'Refresh RO grants' button), or the"
  echo "      agent stays blind to any new tables."
fi
