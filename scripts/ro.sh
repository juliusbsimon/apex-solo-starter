#!/usr/bin/env bash
# Agent-facing READ-ONLY database access via the CLAUDE_RO account.
# Usage:  ro.sh "select ..."          (inline statement)
#         ro.sh path/to/checks.sql    (multi-statement file)
# The repo's .claude/settings.json denies `sql -name*` to the agent;
# this wrapper is the single allowed door, and it can only read.
set -euo pipefail
# Claude Code / cron shells do not source .bashrc - find SQLcl ourselves
command -v sql >/dev/null 2>&1 || PATH="$HOME/sqlcl/bin:$PATH"

ARG="${1:?usage: ro.sh \"select ...\" | ro.sh file.sql}"
CONN="${2:-CLAUDE_RO}"
if [[ -f "$ARG" ]]; then QUERY="$(cat "$ARG")"; else QUERY="$ARG"; fi

sql -name "$CONN" <<SQLEOF
set define off
set pagesize 200 linesize 240 trimspool on
-- CLAUDE_RO owns nothing and has no synonyms; default to the PARSING SCHEMA
-- so queries don't need schema prefixes (needs no extra privilege)
alter session set current_schema = __SCHEMA__;
$QUERY
exit
SQLEOF
