param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][Hashtable]$Options,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

$Options += $PSBoundParameters # Add RepoName, DryRun etc.

# The data license is for the asset download alone, so it leaves the
# environment before anything else runs.
$DataLicense = $env:LICENSE_KEY_DATA_FILES
Remove-Item -Path Env:LICENSE_KEY_DATA_FILES -ErrorAction SilentlyContinue

Write-Host "::group::Configure Git"
./steps/configure-git.ps1 -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Host "::endgroup::"

Write-Host "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Host "::endgroup::"


if ($Options.CI) {
    & "./$RepoName/$($Options.CI)/test.ps1" @Options
    exit $LASTEXITCODE
}

Write-Host "::group::Fetch Assets"
./steps/run-fetch-assets.ps1 -RepoName $RepoName -Options $Options -License $DataLicense
Write-Host "::endgroup::"

Write-Host "::group::Setup Environment"
./steps/run-script.ps1 ./$RepoName/ci/setup-environment.ps1 $Options
Write-Host "::endgroup::"

Write-Host "::group::Install Package From Artifact"
./steps/run-script.ps1 ./$RepoName/ci/install-package.ps1  $Options
Write-Host "::endgroup::"

Write-Host "::group::Run Integration Tests"
./steps/run-script.ps1 ./$RepoName/ci/run-integration-tests.ps1 $Options
Write-Host "::endgroup::"

if ($Options.RunPerformance) {
    Write-Host "::group::Run Performance Tests"
    ./steps/run-script.ps1 ./$RepoName/ci/run-performance-tests.ps1 $Options
    Write-Host "::endgroup::"
}
else {
    Write-Host "Skipping performance tests as they are not configured for '$($Options.Name)'"
}
