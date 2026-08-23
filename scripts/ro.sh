#!/usr/bin/env bash
# Agent-facing READ-ONLY database access via the CLAUDE_RO account
# (db/create-claude-ro.sql sets it up; save the connection once with
#  sql /nolog -> connect -save CLAUDE_RO -savepwd claude_ro/<pw>@//host/svc).
# The repo's .claude/settings.json denies `sql -name*` to the agent;
# this wrapper is the single allowed door, and it can only read.
set -euo pipefail
# Claude Code / cron shells do not source .bashrc - find SQLcl ourselves
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"
QUERY="${1:?usage: ro.sh \"select ...\"}"
CONN="${2:-CLAUDE_RO}"
sql -name "$CONN" <<SQLEOF
set pagesize 200 linesize 240 trimspool on
$QUERY
exit
SQLEOF
