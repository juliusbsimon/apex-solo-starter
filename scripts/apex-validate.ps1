<# Validates the APEXlang sources. No DB connection needed.
   On success, stamps tmp\.validated-<app> with the tree hash so push.ps1
   can skip re-validating an identical tree. #>
param([string]$App = "__APP__")
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"
function Get-TreeHash {
  $c = (Get-ChildItem $path -Recurse -File | Sort-Object FullName |
        ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash + "|" + $_.FullName }) -join "`n"
  (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream][Text.Encoding]::UTF8.GetBytes($c))).Hash
}
$out = @"
apex validate -input $path
exit
"@ | sql /nolog
$out
$stamp = Join-Path $repo "tmp\.validated-$App"
if ($out -match "Validation successful") {
  New-Item -ItemType Directory -Force -Path (Join-Path $repo "tmp") | Out-Null
  Get-TreeHash | Set-Content $stamp -NoNewline
} else {
  Remove-Item $stamp -ErrorAction SilentlyContinue
  Write-Host "`n== findings per file ==" -ForegroundColor Yellow
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
