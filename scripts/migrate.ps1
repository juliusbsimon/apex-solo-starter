<# HUMAN-ONLY. Runs one or more migrations in order, then refreshes the
   CLAUDE_RO account's grants ONCE at the end (promptless). Usage:
   migrate.ps1 -File db\migrations\20260823-01-x.sql[,db\migrations\20260823-02-y.sql] [-Admin ADMIN_CONN]
   Migrations stop at the first failure; the refresh runs only if all succeeded. #>
param(
  [Parameter(Mandatory=$true)][string[]]$File,
  [string]$Admin,
  [switch]$Redo,
  [string]$Conn = "__CONN__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$ledger = Join-Path $repo "db\migrations\applied-$Conn.txt"
$applied = @(); if (Test-Path $ledger) { $applied = Get-Content $ledger }
foreach ($f in $File) {
  if (-not (Test-Path $f)) { throw "no such file: $f" }
}
$n = 0; $ran = 0
foreach ($f in $File) {
  $n++
  $base = Split-Path -Leaf $f
  if (-not $Redo -and $applied -contains $base) {
    Write-Host "== [$n/$($File.Count)] SKIP $base - already applied per applied-$Conn.txt (use -Redo to force) ==" -ForegroundColor Yellow
    continue
  }
  Write-Host "== [$n/$($File.Count)] running $f as $Conn ==" -ForegroundColor Cyan
  @"
set define off
whenever sqlerror exit failure
@$f
exit success
"@ | sql -name $Conn
  if ($LASTEXITCODE -ne 0) { throw "migration failed: $f" }
  if ($applied -notcontains $base) { Add-Content $ledger $base; $applied += $base }
  $ran++
}
if ($ran -eq 0) {
  Write-Host "nothing ran (all selected files already applied) - grants unchanged." -ForegroundColor Yellow
  exit 0
}
Write-Host "REMINDER: commit applied-$Conn.txt with your migration files." -ForegroundColor Yellow
Write-Host "== refreshing CLAUDE_RO grants (no prompt) ==" -ForegroundColor Cyan
if ($Admin) { sql -name $Admin "@$repo\db\refresh-claude-ro-grants.sql" }
else { Write-Host "NOTE: no admin connection given - run scripts\refresh-ro-grants.ps1 -Admin ADMIN_CONN (or the GUI's 'Refresh RO grants' button), or the agent stays blind to new tables." -ForegroundColor Yellow }
