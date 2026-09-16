<# HUMAN-ONLY. Refreshes the read-only agent account's grants (promptless).
   Usage: refresh-ro-grants.ps1 -Admin ADMIN_CONN #>
param([Parameter(Mandatory=$true)][string]$Admin)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Write-Host "== refreshing read-only-account grants as $Admin (no prompt) ==" -ForegroundColor Cyan
sql -name $Admin "@$repo\db\refresh-claude-ro-grants.sql"
