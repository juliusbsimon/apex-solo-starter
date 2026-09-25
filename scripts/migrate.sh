#!/usr/bin/env bash
# HUMAN-ONLY. Runs one or more migrations in order, then refreshes the
# CLAUDE_RO account's grants ONCE at the end (promptless) so the agent can
# see any new tables — the step everyone forgets.
# Usage: migrate.sh [-redo] <file.sql> [<file.sql> ...] [ADMIN_CONN]
#   Every argument that names an existing file is a migration to run.
#   A final argument that is NOT a file is taken as the admin connection
#   name for the grants refresh. Migrations stop at the first failure;
#   the refresh runs only if every migration succeeded.
# Ledger: each file that ran successfully is recorded in
#   db/migrations/applied-<CONN>.txt (COMMIT this file - it is the record
#   of what this connection's database has already received). Files already
#   in the ledger are SKIPPED; -redo runs them anyway.
set -euo pipefail
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
REDO=0
if [[ "${1:-}" == "-redo" ]]; then REDO=1; shift; fi
CONN="__CONN__"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="$REPO/db/migrations/applied-$CONN.txt"

[[ $# -ge 1 ]] || { echo "usage: migrate.sh [-redo] <file.sql> [<file.sql> ...] [ADMIN_CONN]" >&2; exit 1; }

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
ran=0
for FILE in "${FILES[@]}"; do
  n=$((n+1))
  BASE="$(basename "$FILE")"
  if [[ $REDO -eq 0 && -f "$LEDGER" ]] && grep -qxF "$BASE" "$LEDGER"; then
    echo "== [$n/${#FILES[@]}] SKIP $BASE - already applied per $(basename "$LEDGER") (use -redo to force) =="
    continue
  fi
  echo "== [$n/${#FILES[@]}] running $FILE as $CONN =="
  sql -name "$CONN" <<SQLEOF
set define off
whenever sqlerror exit failure
variable mig_t0 varchar2(20)
exec :mig_t0 := to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS')
@$FILE
-- compile gate: "created with compilation errors" is only a WARNING to
-- SQLcl, so whenever sqlerror never fires. Fail the run (and keep the file
-- out of the ledger) if any object this migration touched has errors.
set serveroutput on size unlimited
declare
    n pls_integer := 0;
begin
    for e in ( select e.type, e.name, e.line, e.position, e.text
               from   user_errors e
               join   user_objects o on o.object_name = e.name and o.object_type = e.type
               where  e.attribute = 'ERROR'
               and    o.last_ddl_time >= to_date(:mig_t0, 'YYYY-MM-DD HH24:MI:SS') - 1/86400
               order  by e.type, e.name, e.sequence ) loop
        dbms_output.put_line(e.type || ' ' || e.name || ' line ' || e.line || ':' || e.position || '  ' || e.text);
        n := n + 1;
    end loop;
    if n > 0 then
        raise_application_error(-20100, n || ' compilation error(s) in objects this migration created - NOT recorded as applied');
    end if;
end;
/
-- not fatal: dependents invalidated elsewhere in the schema by this change
select object_type || ' ' || object_name || ' is INVALID (recompile or fix)' warning
from   user_objects where status = 'INVALID' order by 1;
exit success
SQLEOF
  # record success (once) - the ledger is what keeps run-once scripts run-once
  grep -qxF "$BASE" "$LEDGER" 2>/dev/null || echo "$BASE" >> "$LEDGER"
  ran=$((ran+1))
done

if [[ $ran -eq 0 ]]; then
  echo "nothing ran (all selected files already applied) - grants unchanged."
  exit 0
fi
echo "REMINDER: commit $(basename "$LEDGER") with your migration files."
echo "== refreshing read-only-account grants (no prompt) =="
if [[ -n "$ADMIN" ]]; then
  sql -name "$ADMIN" @"$REPO/db/refresh-claude-ro-grants.sql"
else
  echo "NOTE: no admin connection given - run scripts/refresh-ro-grants.sh"
  echo "      ADMIN_CONN (or the GUI's 'Refresh RO grants' button), or the"
  echo "      agent stays blind to any new tables."
fi
