param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    [Parameter(Mandatory=$true)]
    [hashtable]$Options,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

$Options += $PSBoundParameters # Add RepoName, DryRun etc.
if ($Options.Keys) {
    $Options += $Options.Keys # Expand keys into options
}

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Checkout PR"
./steps/checkout-pr.ps1 -RepoName $RepoName -Branch $Branch -PullRequestId $PullRequestId -SetVariable PullRequestSha
Write-Output "pr-sha=$PullRequestSha" | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"

Write-Output "::group::Fetch Assets"
./steps/run-script.ps1 ./$RepoName/ci/fetch-assets.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Setup Environment"
./steps/run-script.ps1 ./$RepoName/ci/setup-environment.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Build Project"
./steps/run-script.ps1 ./$RepoName/ci/build-project.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Run Unit Tests"
./steps/run-script.ps1 ./$RepoName/ci/run-unit-tests.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Run Integration Tests"
./steps/run-script.ps1 ./$RepoName/ci/run-integration-tests.ps1 $Options
Write-Output "::endgroup::"

if ($Options.RunPerformance -eq $True) {
    Write-Output "::group::Run Performance Tests"
    ./steps/run-script.ps1 ./$RepoName/ci/run-performance-tests.ps1 $Options
    Write-Output "::endgroup::"
}
else {
    Write-Output "Skipping performance tests as they are not configured for '$($Options.Name)'"
}
