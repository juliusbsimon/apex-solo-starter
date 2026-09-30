<# Validates the APEXlang sources. No DB connection needed. Same modes as apex-validate.sh.
   Full tree:     apex-validate.ps1 [-App APP]
     On success records the baseline: tmp\.validated-<app> (whole-tree hash)
     and tmp\.validated-<app>.files (one hash per file, for -Changed).
   Changed only:  apex-validate.ps1 -Changed [-App APP]      (what push.ps1 runs)
     nothing changed -> nothing to do; only page files changed/added ->
     validates just those pages; anything else -> full validation.
     The baseline is refreshed by a full pass AND by every successful push.
   Page subset:   apex-validate.ps1 -Pages p00101,p00102 [-App APP]
     shared components + global page + the named pages only. Never updates
     the baseline. It cannot see another page that refers to something you
     renamed or removed; the server-side import checks the whole app and
     refuses it on any error, so that case fails at push, nothing replaced. #>
param(
  [string]$App = "__APP__",
  [switch]$Changed,
  [string[]]$Pages = @()
)
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"
if (-not (Test-Path $path)) { Write-Host "no such app dir: apex\$App" -ForegroundColor Red; exit 1 }
$stamp    = Join-Path $repo "tmp\.validated-$App"
$manifest = "$stamp.files"

# same formula as push.ps1 / promote.ps1 - keep them identical
function Get-TreeHash {
  $c = (Get-ChildItem $path -Recurse -File | Sort-Object FullName |
        ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash + "|" + $_.FullName }) -join "`n"
  (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream][Text.Encoding]::UTF8.GetBytes($c))).Hash
}
# "<sha256>  ./relative/path" per file, sorted
function Get-Manifest {
  $root = (Resolve-Path $path).Path.TrimEnd('\') + '\'
  $lines = Get-ChildItem $path -Recurse -File | ForEach-Object {
    $rel = './' + $_.FullName.Substring($root.Length).Replace('\', '/')
    (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $rel
  }
  [string[]]$arr = @($lines); [Array]::Sort($arr, [StringComparer]::Ordinal); $arr
}
function Show-Findings($out) {
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
}

$mode = if ($Pages.Count -gt 0) { 'pages' } elseif ($Changed) { 'changed' } else { 'full' }

# ---- -Changed: decide between nothing / page subset / full --------------------
if ($mode -eq 'changed') {
  if ((Test-Path $stamp) -and ((Get-Content $stamp -Raw) -eq (Get-TreeHash))) {
    Write-Host "tree unchanged since the last full validation or successful import - nothing to validate" -ForegroundColor Green
    exit 0
  }
  if (-not (Test-Path $manifest)) {
    Write-Host "no per-file baseline yet - full validation this once (later runs only check what changed)" -ForegroundColor Yellow
    $mode = 'full'
  } else {
    $base = @(Get-Content $manifest)
    $cur  = @(Get-Manifest)
    $baseSet = New-Object 'System.Collections.Generic.HashSet[string]' (,[string[]]$base)
    $changedFiles = @($cur | Where-Object { -not $baseSet.Contains($_) } | ForEach-Object { $_.Substring(66) })
    $curPaths = New-Object 'System.Collections.Generic.HashSet[string]' (,[string[]]@($cur | ForEach-Object { $_.Substring(66) }))
    $removed = @($base | ForEach-Object { $_.Substring(66) } | Where-Object { -not $curPaths.Contains($_) })
    $nonPage = @($changedFiles | Where-Object { $_ -notmatch '^\./pages/p\d+(-[^/]*)?\.apx$' })
    if ($changedFiles.Count -eq 0 -and $removed.Count -eq 0) {
      Write-Host "file contents match the baseline - nothing to validate" -ForegroundColor Green
      Get-TreeHash | Set-Content $stamp -NoNewline
      exit 0
    } elseif ($removed.Count -gt 0) {
      Write-Host "files removed since the baseline - full validation:" -ForegroundColor Yellow
      $removed | Select-Object -First 5 | ForEach-Object { "   $_" }
      $mode = 'full'
    } elseif ($nonPage.Count -gt 0) {
      Write-Host "non-page files changed since the baseline - full validation:" -ForegroundColor Yellow
      $nonPage | Select-Object -First 5 | ForEach-Object { "   $_" }
      if ($nonPage.Count -gt 5) { "   ... and $($nonPage.Count - 5) more" }
      $mode = 'full'
    } else {
      $Pages = @($changedFiles | ForEach-Object { if ($_ -match '^\./pages/(p\d+)') { $Matches[1] } } | Sort-Object -Unique)
      Write-Host "only $($Pages.Count) page file(s) changed since the baseline - validating just those" -ForegroundColor Cyan
      $mode = 'pages'
    }
  }
}

# ---- page subset ---------------------------------------------------------------
if ($mode -eq 'pages') {
  $stage = Join-Path $repo "tmp\validate-pages"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Join-Path $stage "pages") | Out-Null
  Get-ChildItem $path -Force | Where-Object { $_.Name -ne 'pages' } |
    ForEach-Object { Copy-Item $_.FullName -Destination $stage -Recurse -Force }
  # global page, if present (pNNNNN-<slug>.apx or bare pNNNNN.apx)
  Get-ChildItem (Join-Path $path "pages") -File | Where-Object { $_.Name -match '^p00000(-.*)?\.apx$' } |
    Copy-Item -Destination (Join-Path $stage "pages")
  foreach ($p in $Pages) {
    $hits = @(Get-ChildItem (Join-Path $path "pages") -File | Where-Object { $_.Name -match ('^' + [regex]::Escape($p) + '(-.*)?\.apx$') })
    if ($hits.Count -eq 0) { Write-Host "no such page file: pages\$p[-*].apx" -ForegroundColor Red; exit 1 }
    $hits | Copy-Item -Destination (Join-Path $stage "pages")
  }
  Write-Host "== page-subset validation ($($Pages -join ' ')) - baseline will NOT be updated ==" -ForegroundColor Cyan
  $out = @"
apex validate -input $stage
exit
"@ | sql /nolog
  $out
  if ($out -match "Validation successful") {
    Write-Host "subset OK (the server-side import still checks the whole app)" -ForegroundColor Green
    exit 0
  }
  Show-Findings $out
  exit 1
}

# ---- full tree -------------------------------------------------------------------
Write-Host "== validating the full tree ($path) - can take minutes on a large app ==" -ForegroundColor Cyan
$out = @"
apex validate -input $path
exit
"@ | sql /nolog
$out
if ($out -match "Validation successful") {
  New-Item -ItemType Directory -Force -Path (Join-Path $repo "tmp") | Out-Null
  Get-TreeHash | Set-Content $stamp -NoNewline
  Get-Manifest | Set-Content $manifest
} else {
  Remove-Item $stamp -ErrorAction SilentlyContinue   # the per-file baseline stays: still the last GOOD tree
  Show-Findings $out
  exit 1
}
