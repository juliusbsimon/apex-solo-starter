<# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
   Run pull.ps1 + review git diff before pushing. #>
param(
  [string]$Conn = "__CONN__",
  [string]$App  = "__APP__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"

& (Join-Path $PSScriptRoot "apex-validate.ps1") -App $App
if ($LASTEXITCODE -ne 0) { throw "validation failed - not importing" }

@"
whenever sqlerror exit failure
apex import -input $path
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0) { throw "import failed" }
Write-Host "Imported. Smoke-test in the browser, then pull.ps1 + commit." -ForegroundColor Green
