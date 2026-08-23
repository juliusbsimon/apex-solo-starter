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
  Write-Host "`n== findings per file ==" -ForegroundColor Yellow
  # File: and Error:/Warning: arrive on separate lines - attribute each
  # finding to the most recent File: line
  $cur = $null; $tot = @{}; $err = @{}
  foreach ($line in ($out -split "`n")) {
    if     ($line -match '^File:\s*(\S+)') { $cur = $Matches[1] }
    elseif ($cur -and $line -match '^(Error|Warning):') {
      $tot[$cur] = 1 + [int]$tot[$cur]
      if ($Matches[1] -eq 'Error') { $err[$cur] = 1 + [int]$err[$cur] }
    }
  }
  $tot.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    $suffix = if ($err[$_.Key]) { " ($($err[$_.Key]) errors)" } else { " (warnings only)" }
    "{0,6}  {1}{2}" -f $_.Value, $_.Key, $suffix
  }
  exit 1
}
