#!/usr/bin/env bash
# HUMAN-ONLY. Runs one migration, then refreshes CLAUDE_RO's grants so the
# agent can see any new tables (the step everyone forgets).
# Usage: migrate.sh db/migrations/20260823-01-something.sql [ADMIN_CONN]
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
FILE="${1:?usage: migrate.sh db/migrations/<file>.sql [ADMIN_CONN]}"
ADMIN="${2:-}"
CONN="__CONN__"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$FILE" ]] || { echo "no such file: $FILE" >&2; exit 1; }
echo "== running $FILE as $CONN =="
sql -name "$CONN" <<SQLEOF
whenever sqlerror exit failure
@$FILE
exit success
SQLEOF

echo "== refreshing read-only-account grants =="
if [[ -n "$ADMIN" ]]; then
  # interactive so the (ignored-on-rerun) password prompt works
  sql -name "$ADMIN" @"$REPO/db/create-claude-ro.sql"
else
  echo "NOTE: no admin connection given - run db/create-claude-ro.sql as admin"
  echo "      yourself, or the agent stays blind to any new tables."
fi
