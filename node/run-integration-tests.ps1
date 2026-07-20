param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host 'Running integration tests'
$env:JEST_JUNIT_OUTPUT_DIR = 'test-results/integration'
npm --prefix $RepoName run integration-test
