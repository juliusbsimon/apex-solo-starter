<# Builder -> repo. Run before editing anything, and after Builder work. #>
param(
  [string]$Conn  = "__CONN__",
  [int]   $AppId = __APP_ID__,
  [string]$App   = "__APP__"
)
$ErrorActionPreference = "Stop"
$repo  = Split-Path -Parent $PSScriptRoot
# stage INSIDE the repo (tmp/ is gitignored): SQLcl export fails with
# "'other' has different root" if stage and cwd are on different drives
$stage = Join-Path $repo "tmp\apex-pull"

# Uncommitted edits under apex\ would be OVERWRITTEN by the mirror below.
$dirty = git -C $repo status --porcelain -- "apex/$App"
if ($dirty) {
  Write-Host "WARNING: uncommitted changes under apex\$App - this pull will ERASE them:" -ForegroundColor Yellow
  git -C $repo status --short -- "apex/$App"
  Write-Host "Commit first (or push your edits), unless you mean to discard them."
  $ans = Read-Host "Overwrite local edits with the Builder version? [y/N]"
  if ($ans -notmatch '^[yY]') { Write-Host "pull aborted." -ForegroundColor Red; exit 1 }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

@"
whenever sqlerror exit failure
whenever oserror  exit failure
apex export -applicationid $AppId -dir "$stage" -exptype apexlang -force
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0) { throw "export failed" }

# If APEXlang export fails engine-side (ORA-01403 in WWV_META_META_DATA: a
# component with incomplete metadata - see runbook troubleshooting), fall back:
#   swap the export line for:  apex export -applicationid $AppId -dir "$stage" -split -skipExportDate
#   and the guard below for:   f$AppId\install.sql + f$AppId\application

$src = (Get-ChildItem $stage -Directory | Select-Object -First 1).FullName
if (-not $src -or -not (Test-Path (Join-Path $src "application.apx"))) {
  throw "export incomplete - not mirroring"
}
robocopy $src (Join-Path $repo "apex\$App") /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

# stamp the pull date: push.ps1 checks `apex list -changesSince <this>` so a
# Builder edit made after this pull is caught before an import clobbers it
Get-Date -Format "yyyy-MM-dd" | Set-Content (Join-Path $repo "tmp\.pulled-$App")

Set-Location $repo
git status --short
