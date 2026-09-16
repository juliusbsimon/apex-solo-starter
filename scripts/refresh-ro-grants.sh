#!/usr/bin/env bash
# HUMAN-ONLY. Refreshes the read-only agent account's grants (promptless).
# Run after adding tables outside migrate.sh, or when migrate printed the
# "no admin connection given" note.
# Usage: refresh-ro-grants.sh ADMIN_CONN
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
ADMIN="${1:?usage: refresh-ro-grants.sh ADMIN_CONN}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "== refreshing read-only-account grants as $ADMIN (no prompt) =="
sql -name "$ADMIN" @"$REPO/db/refresh-claude-ro-grants.sql"
