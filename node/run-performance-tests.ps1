param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Name,
    # The performance example to run, relative to the repository directory.
    [Parameter(Mandatory)][string]$Example
)

$rootDir = $PWD
# Absolute, because the example runs from the repository directory.
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
    # Stop here, so a test failure isn't reported as a missing results file.
    Write-Warning "Performance tests failed, so the results are not published"
    exit 1
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
