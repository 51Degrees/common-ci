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
    [Hashtable]$Options,
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

Write-Output "::group::Fetch Assets"
./steps/run-script.ps1 ./$RepoName/ci/fetch-assets.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Setup Environment"
./steps/run-script.ps1 ./$RepoName/ci/setup-environment.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Build Package Requirements"
./steps/run-script.ps1 ./$RepoName/ci/build-package-requirements.ps1 $Options
Write-Output "::endgroup::"
