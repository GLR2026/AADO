<#
AADO-COMM-001
Round Manager Launcher

Version: 0.1.0
Status: SKELETON

Initial mode:
Console / deterministic.
GUI will come later.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ModulePath = Join-Path $PSScriptRoot "RoundManagerCore.psm1"

if (-not (Test-Path $ModulePath)) {
    throw "RoundManagerCore.psm1 not found."
}

Import-Module $ModulePath -Force

Write-Host ""
Write-Host "AADO Round Manager"
Write-Host "Version 0.1.0"
Write-Host "Core loaded successfully."
Write-Host ""
Write-Host "No workflow functions implemented yet."

