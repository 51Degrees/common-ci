param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Version
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $Version) {
    $Version = git -C $RepoName describe --tags --abbrev=0
}

# Bump patch version component
if ($Version -cmatch '(.*)\.(\d+)$') {
    $newVersion = "$($Matches.1).$([int]$Matches.2 + 1)"
    Write-Host "Bumping $Version to $newVersion"
    return $newVersion
}

Write-Error "Failed to parse version: $Version"
