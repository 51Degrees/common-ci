<#
.SYNOPSIS
Runs a PHP performance example and publishes the results JSON it emits.

.DESCRIPTION
The example writes its own results JSON in the shared schema (see
steps/publish-performance-results.ps1), so this adapter only runs it and hands
the file over. It does not parse the example's console output.
#>
param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Name,
    # The performance example to run, relative to the repository directory.
    [Parameter(Mandatory)][string]$Example
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$rootDir = $PWD
# An absolute path, because the example runs with the repository as its working
# directory.
$resultsFile = Join-Path $rootDir "results_$Name.json"
Remove-Item -Path $resultsFile -Force -ErrorAction SilentlyContinue

Push-Location $RepoName
try {
    Write-Output "Running performance tests"
    php $Example --json-output $resultsFile
} finally {
    Pop-Location
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
