param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$GitHubToken,
    [Parameter(Mandatory)][Hashtable]$Options,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

$Options += $PSBoundParameters # Add RepoName, DryRun etc.
if ($Options.Keys) {
    $Options += $Options.Keys # Expand keys into options
}

Write-Host "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Host "::endgroup::"

Write-Host "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Host "::endgroup::"

if ($Options.CI) {
    & "./$RepoName/$($Options.CI)/test.ps1" @Options
    exit
}

Write-Host "::group::Fetch Assets"
./steps/run-script.ps1 ./$RepoName/ci/fetch-assets.ps1 $Options
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
