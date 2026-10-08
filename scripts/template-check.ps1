<# Is the apex-solo-starter template newer than what this project last
   updated from? Prints ONE line when it is; silent when current. Never
   fails the caller. Same logic and cache file as template-check.sh. #>
try {
  $repo  = Split-Path -Parent $PSScriptRoot
  $url   = "https://github.com/juliusbsimon/apex-solo-starter.git"
  $cache = Join-Path $repo "tmp\.template-check"
  $today = Get-Date -Format "yyyy-MM-dd"
  $latest = ""
  if ((Test-Path $cache) -and ((Get-Content $cache -Raw).Trim() -split ' ')[0] -eq $today) {
    $latest = ((Get-Content $cache -Raw).Trim() -split ' ')[1]
  } else {
    $job = Start-Job { param($u) git ls-remote $u refs/heads/main 2>$null } -ArgumentList $url
    if (Wait-Job $job -Timeout 5) { $out = Receive-Job $job }
    Remove-Job $job -Force
    if (-not $out) { return }
    $latest = ("$out" -split "\s+")[0]
    New-Item -ItemType Directory -Force -Path (Join-Path $repo "tmp") | Out-Null
    "$today $latest" | Set-Content $cache
  }
  if (-not $latest) { return }
  $verFile = Join-Path $repo ".template-version"
  $mine = if (Test-Path $verFile) { ((Get-Content $verFile | Select-Object -First 1) -split ' ')[0] } else { "" }
  if (-not $mine) {
    Write-Host "TEMPLATE: this project's template version is unknown - run the updater once (bash scripts/update-from-template.sh, from WSL or Git Bash) to record it." -ForegroundColor Yellow
  } elseif ($mine -ne $latest) {
    Write-Host ("TEMPLATE: update available (yours {0}, latest {1}) - run bash scripts/update-from-template.sh (WSL or Git Bash) when convenient." -f $mine.Substring(0,7), $latest.Substring(0,7)) -ForegroundColor Yellow
  }
} catch { }
