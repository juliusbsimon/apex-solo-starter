<# One-time project setup from the apex-solo-starter archive.
   Unzip into an empty folder (short path, e.g. D:\dev\myapp), then:
     powershell -ExecutionPolicy Bypass -File .\init.ps1
   Prompts for the per-project values, stamps them into every file,
   initializes git, and prints the remaining manual steps. #>
$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot
Set-Location $repo

$app      = Read-Host "Short app name, lowercase, no spaces (e.g. portal)"
$appTitle = Read-Host "App title (e.g. ACME - Order Tracking)"
$appId    = Read-Host "DEV application id (e.g. 139)"
$ws       = Read-Host "APEX workspace name (e.g. ACME)"
$schema   = Read-Host "Parsing schema (blank = same as workspace; they often differ!)"
if (-not $schema) { $schema = $ws }
$conn     = Read-Host "SQLcl connection name to create/use (e.g. $($app.ToUpper())_DEV)"

if (-not ($appId -match '^\d+$')) { throw "application id must be a number" }

$tokens = @{
  "__APP__"       = $app
  "__APP_TITLE__" = $appTitle
  "__APP_ID__"    = $appId
  "__WORKSPACE__" = $ws
  "__SCHEMA__"    = $schema
  "__CONN__"      = $conn
}

Get-ChildItem -Recurse -File -Include *.ps1,*.md,*.sql,*.json |
  Where-Object { $_.Name -ne "init.ps1" } |
  ForEach-Object {
    $c = Get-Content $_.FullName -Raw
    $orig = $c
    foreach ($k in $tokens.Keys) { $c = $c.Replace($k, $tokens[$k]) }
    if ($c -ne $orig) { Set-Content $_.FullName $c -Encoding utf8 -NoNewline }
  }

New-Item -ItemType Directory -Force -Path "apex\$app" | Out-Null
Remove-Item "apex\.gitkeep" -ErrorAction SilentlyContinue

if (-not (Test-Path ".git")) { git init -b main | Out-Null }

Write-Host ""
Write-Host "Stamped. Remaining steps:" -ForegroundColor Green
Write-Host "  1. Save the connection (parsing schema of workspace $ws):"
Write-Host "       sql /nolog"
Write-Host "       connect -save $conn -savepwd schema/<password>@//host:1521/service"
Write-Host "  2. (Optional, recommended) Agent read-only account:"
Write-Host "       run db\create-claude-ro.sql as an admin user - schema is stamped"
Write-Host "       and it prompts for a password, nothing to edit - then:"
Write-Host "       then: connect -save `$($app)_CLAUDE_RO -savepwd `$($app)_claude_ro/<pw>@//host:1521/service"
Write-Host "  3. Baseline:  .\scripts\pull.ps1   then review, and:"
Write-Host "       git add -A ; git commit -m 'chore: baseline APEXlang export of $app'"
Write-Host "  4. Remote:    git remote add origin <url> ; git push -u origin main"
Write-Host "  5. Determinism check: pull.ps1 again -> git status must be clean."
Write-Host "  6. Validate the baseline: .\scripts\apex-validate.ps1 - old apps often"
Write-Host "     export with Builder-side errors; fix them before relying on push."
Write-Host ""
Write-Host "  This checklist also lives in RUNBOOK.md SS2 'Setup at a glance'."
Write-Host ""
Write-Host "  Then read RUNBOOK.md - especially the daily loop (SS3) and guardrails (SS3b)."
Write-Host "  You can delete init.ps1 now."
