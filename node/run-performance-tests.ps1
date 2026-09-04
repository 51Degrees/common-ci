<#
.SYNOPSIS
Runs a Node performance example and publishes the results JSON it emits.

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

$rootDir = $PWD
# An absolute path, because the example runs with the repository as its working
# directory.
$resultsFile = Join-Path $rootDir "results_$Name.json"
Remove-Item -Path $resultsFile -Force -ErrorAction SilentlyContinue

$testsFailed = $false
Push-Location $RepoName
try {
    Write-Output "Running performance tests"
    $env:JEST_JUNIT_OUTPUT_DIR = 'test-results/performance'

    node $Example --jsonoutput $resultsFile || $($testsFailed = $true)
} finally {
    Pop-Location
}

if ($testsFailed) {
    # Report the test failure rather than letting the publish step fail with a
    # missing-results-file error, which would hide the real cause.
    Write-Warning "Performance tests failed, so the results are not published"
    exit 1
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
