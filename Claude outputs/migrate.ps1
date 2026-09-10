<# HUMAN-ONLY. Runs one or more migrations in order, then refreshes the
   CLAUDE_RO account's grants ONCE at the end (promptless). Usage:
   migrate.ps1 -File db\migrations\20260823-01-x.sql[,db\migrations\20260823-02-y.sql] [-Admin ADMIN_CONN]
   Migrations stop at the first failure; the refresh runs only if all succeeded. #>
param(
  [Parameter(Mandatory=$true)][string[]]$File,
  [string]$Admin,
  [string]$Conn = "__CONN__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
foreach ($f in $File) {
  if (-not (Test-Path $f)) { throw "no such file: $f" }
}
$n = 0
foreach ($f in $File) {
  $n++
  Write-Host "== [$n/$($File.Count)] running $f as $Conn ==" -ForegroundColor Cyan
  @"
set define off
whenever sqlerror exit failure
@$f
exit success
"@ | sql -name $Conn
  if ($LASTEXITCODE -ne 0) { throw "migration failed: $f" }
}
Write-Host "== refreshing CLAUDE_RO grants (no prompt) ==" -ForegroundColor Cyan
if ($Admin) { sql -name $Admin "@$repo\db\refresh-claude-ro-grants.sql" }
else { Write-Host "NOTE: run db\refresh-claude-ro-grants.sql as admin yourself, or the agent stays blind to new tables." -ForegroundColor Yellow }
