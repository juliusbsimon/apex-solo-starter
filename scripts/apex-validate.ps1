<# Validates the APEXlang sources. No DB connection needed. #>
param([string]$App = "__APP__")
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"
$out = @"
apex validate -input $path
exit
"@ | sql /nolog
$out
if ($out -notmatch "Validation successful") {
  Write-Host "`n== errors/warnings per file ==" -ForegroundColor Yellow
  ($out -split "`n") | Where-Object { $_ -match '(?i)error|warning' } |
    ForEach-Object { if ($_ -match '(\S+\.apx)') { $Matches[1] } } |
    Group-Object | Sort-Object Count -Descending |
    ForEach-Object { "{0,6}  {1}" -f $_.Count, $_.Name }
  exit 1
}
