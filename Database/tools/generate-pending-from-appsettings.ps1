#requires -Version 5.1
<#
.SYNOPSIS
  Reads DB connection info out of an appsettings.*.json file and generates
  the combined pending-migrations script for that database. Invoked
  automatically by `dotnet publish` (see Web_Backend.csproj).
#>
param(
    [Parameter(Mandatory = $true)][string]$AppSettingsPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $AppSettingsPath)) {
    Write-Warning "appsettings file not found at $AppSettingsPath — skipping migration script generation. (Expected locally: this file is gitignored and only exists once you've set up appsettings.Production.json.)"
    return
}

$settings = Get-Content $AppSettingsPath -Raw | ConvertFrom-Json
$db = $settings.ApplicationSettings.DBSettings

if (-not $db -or -not $db.Server -or -not $db.Database) {
    Write-Warning "DBSettings missing/empty in $AppSettingsPath — skipping migration script generation."
    return
}

$applyScript = Join-Path $PSScriptRoot "apply-migrations.ps1"

$params = @{
    Server       = $db.Server
    Database     = $db.Database
    GenerateOnly = $true
}
if ($db.UserId) {
    $params.UserId = $db.UserId
    $params.Password = $db.Password
}

& $applyScript @params
