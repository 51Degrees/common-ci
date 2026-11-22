# Makes sure the one GitVersion version this repository is written for is the
# one installed, and fails if it is not. Having some GitVersion is not
# enough, because a runner can already carry another version and its output
# differs from one version to the next.
#
# This is the only place the version is set. Every workflow, action and step
# that needs GitVersion runs this script first. To move to another version,
# change the default below and nothing else.
param (
    [string]$Version = '6.8.2'
)

# The installed version, or $null when GitVersion is missing or does not
# answer with a version. A pre-release is not the release, so it is $null.
function Get-InstalledGitVersion {
    try {
        $output = dotnet-gitversion /version 2>$null | Select-Object -First 1
    } catch {
        return $null
    }
    $match = [regex]::Match([string]$output, '^([0-9]+[.][0-9]+[.][0-9]+)([+].*)?$')
    if ($match.Success -eq $false) {
        return $null
    }
    return $match.Groups[1].Value
}

# Installs GitVersion at $Version, or changes the installed one to it, then
# checks the version that is installed.
function Install-GitVersion([string]$Version) {
    if ($Version -notmatch '^[0-9]+[.][0-9]+[.][0-9]+$') {
        throw "GitVersion must be pinned to an exact version such as 6.8.2, not '$Version'."
    }

    $installed = Get-InstalledGitVersion
    if ($installed -eq $Version) {
        Write-Host "GitVersion $Version is already installed."
        return
    }

    if ($null -eq $installed) {
        Write-Host "GitVersion is not installed. Installing $Version."
    } else {
        Write-Host "GitVersion $installed is installed. Changing it to $Version."
    }
    $global:LASTEXITCODE = 0
    # Out-Host keeps the tool's output out of what a caller captures.
    # --allow-downgrade lets the SDK move a newer GitVersion down to $Version.
    # Without it the update is refused and a runner that carries GitVersion 7
    # keeps it. The flag needs .NET SDK 8.0.200 or later.
    dotnet tool update --global GitVersion.Tool --version $Version --allow-downgrade | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet tool update for GitVersion $Version failed with exit code $LASTEXITCODE."
    }

    $installed = Get-InstalledGitVersion
    if ($installed -ne $Version) {
        $found = if ($installed) { $installed } else { 'none' }
        throw "GitVersion $found is installed after the update, not $Version."
    }
    Write-Host "GitVersion $Version is installed."
}

# Dot-sourcing, as the tests do, only defines the functions.
if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    Install-GitVersion -Version $Version
}
