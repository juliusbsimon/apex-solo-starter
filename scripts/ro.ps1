<# Agent-facing READ-ONLY database access via the CLAUDE_RO account
   (db/create-claude-ro.sql sets it up; save the connection once with
   sql /nolog -> connect -save CLAUDE_RO -savepwd claude_ro/<pw>@//host/svc).
   The repo's .claude/settings.json denies `sql -name*` to the agent;
   this wrapper is the single allowed door, and it can only read. #>
param(
  [Parameter(Mandatory=$true)][string]$Query,
  [string]$Conn = "CLAUDE_RO"
)
@"
set pagesize 200 linesize 240 trimspool on
$Query
exit
"@ | sql -name $Conn
