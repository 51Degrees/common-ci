param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $RepoName
try {
    Write-Host 'Running unit tests'
    $env:JEST_JUNIT_OUTPUT_DIR = 'test-results/unit'
    npm run unit-test
} finally { Pop-Location }
