<# HUMAN-ONLY. Runs one migration, then refreshes CLAUDE_RO's grants so the
   agent can see any new tables. Usage:
   migrate.ps1 -File db\migrations\20260823-01-x.sql [-Admin ADMIN_CONN] #>
param(
  [Parameter(Mandatory=$true)][string]$File,
  [string]$Admin,
  [string]$Conn = "__CONN__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $File)) { throw "no such file: $File" }
Write-Host "== running $File as $Conn ==" -ForegroundColor Cyan
@"
whenever sqlerror exit failure
@$File
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0) { throw "migration failed" }
Write-Host "== refreshing CLAUDE_RO grants ==" -ForegroundColor Cyan
if ($Admin) { sql -name $Admin "@$repo\db\create-claude-ro.sql" }
else { Write-Host "NOTE: run db\create-claude-ro.sql as admin yourself, or the agent stays blind to new tables." -ForegroundColor Yellow }
