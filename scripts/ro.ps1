<# Agent-facing READ-ONLY database access via the CLAUDE_RO account.
   Usage:  ro.ps1 -Query "select ..."      (inline)
           ro.ps1 -File path\to\checks.sql (multi-statement file)
   The repo's .claude/settings.json denies `sql -name*` to the agent;
   this wrapper is the single allowed door, and it can only read. #>
param(
  [string]$Query,
  [string]$File,
  [string]$Conn = "CLAUDE_RO"
)
if ($File) { $Query = Get-Content $File -Raw }
if (-not $Query) { throw "usage: ro.ps1 -Query `"select ...`"  or  -File checks.sql" }
@"
set define off
set pagesize 200 linesize 240 trimspool on
alter session set current_schema = __SCHEMA__;
$Query
exit
"@ | sql -name $Conn
