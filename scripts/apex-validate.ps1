<# Validates the APEXlang sources. No DB connection needed. #>
param([string]$App = "__APP__")
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"
$out = @"
apex validate -input $path
exit
"@ | sql /nolog
$out
if ($out -notmatch "Validation successful") { exit 1 }
