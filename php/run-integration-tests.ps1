param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Different tests require different environment variables, so they should be
# set by the caller, e.g.:
#   $env:RESOURCEKEY = $Keys.TestResourceKey

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
