<# Verifies machine prerequisites on Windows; prints install commands for
   anything missing. Nothing is installed automatically. #>
$ok = $true
function Check($name, $cmd, $hint) {
  try {
    $v = & $cmd 2>&1 | Select-Object -First 1
    Write-Host ("  [ok] {0,-8} {1}" -f $name, $v) -ForegroundColor Green
  } catch {
    Write-Host ("  [--] {0,-8} MISSING  -> {1}" -f $name, $hint) -ForegroundColor Yellow
    $script:ok = $false
  }
}
Write-Host "Prerequisites:"
Check "java"  { java -version }  "winget install EclipseAdoptium.Temurin.21.JRE"
Check "git"   { git --version }  "winget install Git.Git"
Check "sqlcl" { sql -V }         "download sqlcl-latest.zip from oracle.com/sqlcl, unzip to C:\tools\sqlcl, add C:\tools\sqlcl\bin to PATH"

if ($ok) {
  Write-Host "`nAll present. Per-machine leftovers:" -ForegroundColor Green
  Write-Host "  - execution policy (once):  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
  Write-Host "  - saved connections (per project + CLAUDE_RO):  sql /nolog  ->  connect -save ..."
  Write-Host "  - SQLcl must be >= your APEX version for APEXlang exports"
} else {
  Write-Host "`nInstall the missing items above, reopen the terminal, re-run this check."
}
