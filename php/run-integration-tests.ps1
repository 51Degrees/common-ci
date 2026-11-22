param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The tests read their keys from the environment, under the _51DEGREES_ names
# the workflow exports.

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
    phpunit $options --testsuite Integration --log-junit test-results/integration/$RepoName/tests.xml
} finally {
    Pop-Location
}
