param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$options = @("--fail-on-warning")
& {
    $PSNativeCommandUseErrorActionPreference = $false
    phpunit --atleast-version=10 | Out-Null
}
if ($LASTEXITCODE -eq 0) {
    $options += "--display-warnings"
}

Push-Location $RepoName
try {
    phpunit $options --testsuite Unit --log-junit test-results/unit/$RepoName/tests.xml
} finally {
    Pop-Location
}
