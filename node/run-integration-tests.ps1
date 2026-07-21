param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $RepoName
try {
    Write-Host 'Running integration tests'
    $env:JEST_JUNIT_OUTPUT_DIR = 'test-results/integration'
    npm run integration-test
} finally { Pop-Location }
