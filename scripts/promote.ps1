<# HUMAN-ONLY. Promote a working copy to the MAIN app by replace.
   Usage: promote.ps1 -Target MAIN_APP_ID [-App SRC_APP_DIR] [-Conn CONN] [-Workspace WS]
   Same procedure as promote.sh: target sanity, validate, MANDATORY backup
   of main, typed confirmation (type the main app id), import keeping main's
   id/name/alias, then the manual post-steps. #>
param(
  [Parameter(Mandatory=$true)][int]$Target,
  [string]$App       = "__APP__",
  [string]$Conn      = "__CONN__",
  [string]$Workspace = "__WORKSPACE__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $repo "apex\$App"
if (-not (Test-Path $src)) { throw "no such app dir: apex\$App" }
$srcId = (Get-ChildItem (Join-Path $src "deployments\*.json") | Get-Content -Raw |
          Select-String '"id"\s*:\s*(\d+)').Matches | Select-Object -First 1 | ForEach-Object { $_.Groups[1].Value }
if ("$srcId" -eq "$Target") { throw "apex\$App IS app $Target - that's a normal push, not a promote. Use push.ps1." }

# 1. target sanity
Write-Host "== looking up main app $Target ==" -ForegroundColor Cyan
$meta = @"
set heading off feedback off pagesize 0 linesize 4000 define off
select 'META|' || application_name || '|' || alias || '|' ||
       to_char(last_updated_on, 'YYYY-MM-DD HH24:MI') || '|' || last_updated_by || '|' || pages
from   apex_applications where application_id = $Target;
exit
"@ | sql -S -name $Conn
$line = $meta | Where-Object { $_ -like 'META|*' } | Select-Object -First 1
if (-not $line) { throw "app $Target not found in this workspace - wrong id or connection" }
$null, $tName, $tAlias, $tUpd, $tBy, $tPages = $line -split '\|'
if ($tName -like '*(Working Copy:*') { throw "app $Target is itself a working copy ('$tName'). Promote targets the MAIN app only." }

# 2. validate (cache-skip on unchanged tree)
function Get-TreeHash {
  $c = (Get-ChildItem $src -Recurse -File | Sort-Object FullName |
        ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash + "|" + $_.FullName }) -join "`n"
  (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream][Text.Encoding]::UTF8.GetBytes($c))).Hash
}
$stamp = Join-Path $repo "tmp\.validated-$App"
if ((Test-Path $stamp) -and ((Get-Content $stamp -Raw) -eq (Get-TreeHash))) {
  Write-Host "source unchanged since last successful validation - skipping validate" -ForegroundColor Green
} else {
  Write-Host "== validating apex\$App before promote ==" -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot "apex-validate.ps1") -App $App
  if ($LASTEXITCODE -ne 0) { throw "validation failed - not promoting" }
}

# 3. mandatory backup
$bk = Join-Path $repo ("tmp\backup-promote-$Target-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $bk | Out-Null
Write-Host "== backing up main app $Target to $bk (rollback artifact) ==" -ForegroundColor Cyan
@"
set define off
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $Target -dir "$bk" -split -skipExportDate
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $bk "f$Target\install.sql"))) { throw "backup export incomplete - NOT promoting" }

# 4. typed confirmation
Write-Host ""
Write-Host "================================ PROMOTE =================================" -ForegroundColor Yellow
Write-Host " REPLACE  main app $Target  `"$tName`"  (alias: $(if ($tAlias) { $tAlias } else { 'none' }))"
Write-Host "          $tPages pages, last changed $tUpd by $tBy"
Write-Host " WITH     apex\$App  (working copy app $srcId)"
Write-Host " KEEPS    main's id, name and alias"
Write-Host " BACKUP   $bk"
Write-Host " AFTER    every automation / REST sync in app $Target is DISABLED until"
Write-Host "          you run scripts\prod-promote\*.sql"
Write-Host " CHECK    nobody changed app $Target since this working copy was cut"
Write-Host "==========================================================================" -ForegroundColor Yellow
$confirm = Read-Host "Type the main app id ($Target) to confirm"
if ($confirm -ne "$Target") { Write-Host "confirmation did not match - promote aborted, nothing changed." -ForegroundColor Red; exit 1 }

# 5. import over main, keeping main's identity
$aliasArg = if ($tAlias) { "-alias $tAlias" } else { "" }
Write-Host "== promoting: importing apex\$App over app $Target ==" -ForegroundColor Cyan
$out = @"
set define off
apex import -input $src -id $Target -name "$tName" $aliasArg -workspace $Workspace
exit
"@ | sql -name $Conn
$out
if ($out -notmatch '(?i)import successful') {
  Write-Host "PROMOTE DID NOT SUCCEED - read the output above." -ForegroundColor Red
  Write-Host "If the import started, app $Target may be partly replaced: restore from $bk" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "PROMOTED: app $Target now runs apex\$App. Remaining steps (manual, on purpose):" -ForegroundColor Green
Write-Host "  1. Re-enable scheduled jobs: scripts\prod-promote\*.sql, then confirm one automation fires."
Write-Host "  2. Smoke-test app $Target in the browser."
Write-Host "  3. Retire the promoted working copy and cut a fresh one from app $Target (new app id)."
Write-Host "  Rollback artifact: $bk"
