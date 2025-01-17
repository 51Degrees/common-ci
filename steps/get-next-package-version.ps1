param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Version
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $Version) {
    $Version = git -C $RepoName name-rev --name-only --tags HEAD
    if ($Version -eq 'undefined') {
        $Version = git -C $RepoName describe --tags --abbrev=0
        $Version = (git -C $RepoName tag --points-at $Version "--sort=-v:refname")?[0] # ensure we're using the biggest of possible multiple tags
    } else {
        Write-Host "HEAD is already tagged: $Version"
        return $Version # return existing tag if tagged
    }
}

# Bump patch version component
if ($Version -cmatch '(.*)\.(\d+)$') {
    $newVersion = "$($Matches.1).$([int]$Matches.2 + 1)"
    Write-Host "Bumping $Version to $newVersion"
    return $newVersion
}

Write-Error "Failed to parse version: $Version"
