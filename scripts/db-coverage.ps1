<# Lists database source files that changed but that NO pending migration
   deploys. Read-only: git and file reads, no database. Same rules as
   db-coverage.sh (see there). Usage: db-coverage.ps1 [-Conn CONN]
   Exit 0 = all covered, 1 = something isn't. #>
param([string]$Conn = "__CONN__")
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
  git rev-parse --git-dir *> $null
  if ($LASTEXITCODE -ne 0) { exit 0 }
  $ledgerRel = "db/migrations/applied-$Conn.txt"
  $applied = @(); if (Test-Path $ledgerRel) { $applied = @(Get-Content $ledgerRel) }
  $base = git log -1 --format=%H -- $ledgerRel 2>$null
  $changed = @(git status --porcelain -uall -- db 2>$null | ForEach-Object { ($_.Substring(3) -split ' -> ')[-1].Trim('"') })
  if ($base) { $changed += @(git diff --name-only $base HEAD -- db 2>$null) }
  $changed = $changed | Where-Object { $_ } | Sort-Object -Unique
  $pending = @(Get-ChildItem db/migrations -Filter *.sql -File -ErrorAction SilentlyContinue |
               Where-Object { $applied -notcontains $_.Name })
  $pendingText = ($pending | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $missing = @()
  foreach ($f in $changed) {
    if (-not ($f -like 'db/*.sql') -or $f -like 'db/migrations/*' -or -not (Test-Path $f)) { continue }
    $leaf = Split-Path -Leaf $f
    if ($leaf -in @('create-claude-ro.sql', 'refresh-claude-ro-grants.sql')) { continue }
    if (-not $pendingText.Contains($leaf)) { $missing += $f }
  }
  if ($missing.Count -gt 0) {
    Write-Host "NOT DEPLOYED BY ANY PENDING MIGRATION (changed db sources):" -ForegroundColor Yellow
    foreach ($f in $missing) { Write-Host ("   {0}      -> add to a migration:  @@../{1}" -f $f, $f.Substring(3)) -ForegroundColor Yellow }
    Write-Host "   (or carry the code inline in the migration) - otherwise it never reaches the database." -ForegroundColor Yellow
    exit 1
  }
  exit 0
} finally { Pop-Location }
