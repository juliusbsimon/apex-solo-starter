<# repo -> Builder. HUMAN-ONLY: this REPLACES the entire application.
   Run pull.ps1 + review git diff before pushing. Skips the local
   pre-validate when the tree hash matches the last validation stamp
   (the import still validates server-side regardless). #>
param(
  [string]$Conn = "__CONN__",
  [string]$App  = "__APP__"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"
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
  Write-Host "Imported. Smoke-test in the browser, then pull.ps1 + commit." -ForegroundColor Green
} else {
  Write-Host "IMPORT DID NOT SUCCEED - read the output above. Nothing was replaced." -ForegroundColor Red
  exit 1
}
