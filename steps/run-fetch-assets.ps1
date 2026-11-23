<#
.SYNOPSIS
    Runs a repository's ci/fetch-assets.ps1 with the data license.

.DESCRIPTION
    The repository's script, and the download steps it calls, read the data
    license as _51DEGREES_LICENSE_KEY. The license given here is set under
    that name while the script runs, and the variable is put back as it was
    afterwards, so the build and the tests that follow in the same step never
    see the data license.

.PARAMETER RepoName
    The folder the repository is cloned into.

.PARAMETER Options
    The matrix options, handed to the script by steps/run-script.ps1.

.PARAMETER License
    The data license, from LICENSE_KEY_DATA_FILES. With none, the script runs
    without _51DEGREES_LICENSE_KEY and fetches the free assets alone.
#>
param(
    [Parameter(Mandatory)][string]$RepoName,
    [hashtable]$Options = @{},
    [string]$License
)
$ErrorActionPreference = "Stop"

$before = [Environment]::GetEnvironmentVariable('_51DEGREES_LICENSE_KEY')
try {
    if ([string]::IsNullOrEmpty($License)) {
        Remove-Item -Path Env:_51DEGREES_LICENSE_KEY -ErrorAction SilentlyContinue
    } else {
        $env:_51DEGREES_LICENSE_KEY = $License
    }
    & $PSScriptRoot/run-script.ps1 ./$RepoName/ci/fetch-assets.ps1 $Options
} finally {
    if ($null -eq $before) {
        Remove-Item -Path Env:_51DEGREES_LICENSE_KEY -ErrorAction SilentlyContinue
    } else {
        $env:_51DEGREES_LICENSE_KEY = $before
    }
}
