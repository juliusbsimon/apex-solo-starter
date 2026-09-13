<# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
   Run pull.ps1 + review git diff before pushing.
   Usage: push.ps1 [-Backup] [-Conn CONN] [-App APP]
     -Backup  full split export of the CURRENT target app into tmp\ before
              importing (minutes on a big app; git already holds the last
              pulled state, so this is belt-and-braces, not required).
   Gates: 1) drift - `apex list -changesSince <last pull date>`: a Builder
   edit made after your pull would be silently erased by the import.
   2) validate - skipped when the tree hash matches the last validation
   stamp (the import still validates server-side regardless). #>
param(
  [switch]$Backup,
  [string]$Conn = "__CONN__",
  [string]$App  = "__APP__"
)
$ErrorActionPreference = "Stop"
$repo  = Split-Path -Parent $PSScriptRoot
$path  = Join-Path $repo "apex\$App"
$appId = "__APP_ID__"

# ---- gate 1: drift since last pull ------------------------------------------
# Date granularity is one day, so pushes on the pull day can list your own
# activity - that is why this asks instead of refusing outright.
$pullStamp = Join-Path $repo "tmp\.pulled-$App"
if (Test-Path $pullStamp) {
  $since = (Get-Content $pullStamp -Raw).Trim()
  Write-Host "== drift check: Builder changes since last pull ($since) ==" -ForegroundColor Cyan
  $drift = @"
apex list -changesSince $since
exit
"@ | sql -name $Conn
  if ($drift -match $appId) {
    $drift
    Write-Host "WARNING: app $appId changed in the Builder on/after $since." -ForegroundColor Yellow
    Write-Host "If that was someone else (or you, in the Builder), STOP: pull," -ForegroundColor Yellow
    Write-Host "diff, and merge first - the import ERASES those changes." -ForegroundColor Yellow
    Write-Host "If it is only your own pull/push activity from that day, continue."
    $ans = Read-Host "Continue push anyway? [y/N]"
    if ($ans -notmatch '^[yY]') { Write-Host "push aborted." -ForegroundColor Red; exit 1 }
  } else {
    Write-Host "no Builder changes since last pull." -ForegroundColor Green
  }
} else {
  Write-Host "NOTE: no pull stamp (tmp\.pulled-$App) - cannot check Builder drift." -ForegroundColor Yellow
  $ans = Read-Host "Continue without the drift check? [y/N]"
  if ($ans -notmatch '^[yY]') { Write-Host "push aborted." -ForegroundColor Red; exit 1 }
}

# ---- optional: backup the current target before replacing it -----------------
if ($Backup) {
  $bk = Join-Path $repo ("tmp\backup-$App-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  New-Item -ItemType Directory -Path $bk | Out-Null
  Write-Host "== backing up current app $appId to $bk (split export) ==" -ForegroundColor Cyan
  @"
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $appId -dir "$bk" -split -skipExportDate
exit success
"@ | sql -name $Conn
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $bk "f$appId\install.sql"))) {
    throw "backup export incomplete - not importing"
  }
}

# ---- gate 2: validate (cache-skip on unchanged tree) --------------------------
function Get-TreeHash {
  $c = (Get-ChildItem $path -Recurse -File | Sort-Object FullName |
        ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash + "|" + $_.FullName }) -join "`n"
  (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream][Text.Encoding]::UTF8.GetBytes($c))).Hash
}
$stamp = Join-Path $repo "tmp\.validated-$App"
if ((Test-Path $stamp) -and ((Get-Content $stamp -Raw) -eq (Get-TreeHash))) {
  Write-Host "tree unchanged since last successful validation - skipping pre-validate" -ForegroundColor Green
} else {
  & (Join-Path $PSScriptRoot "apex-validate.ps1") -App $App
  if ($LASTEXITCODE -ne 0) { throw "validation failed - not importing" }
}
# `apex` is a SQLcl command, not SQL - exit codes don't reflect its failures.
# Judge success from the output, and pass the workspace explicitly (a schema
# granted to multiple workspaces makes an unqualified import bail silently).
$out = @"
apex import -input $path -workspace __WORKSPACE__
exit
"@ | sql -name $Conn
$out
if ($out -match '(?i)import successful') {
  # target now equals the repo, so today becomes the new drift baseline
  Get-Date -Format "yyyy-MM-dd" | Set-Content $pullStamp
  Write-Host "Imported. Smoke-test in the browser, then pull.ps1 + commit." -ForegroundColor Green
  Write-Host "NOTE: the import disabled any scheduled jobs in the target app." -ForegroundColor Yellow
  Write-Host "      Dev apps: usually fine. PRODUCTION promote: run the manual" -ForegroundColor Yellow
  Write-Host "      re-enable scripts - see scripts\prod-promote\README.md" -ForegroundColor Yellow
} else {
  Write-Host "IMPORT DID NOT SUCCEED - read the output above. Nothing was replaced." -ForegroundColor Red
  exit 1
}
