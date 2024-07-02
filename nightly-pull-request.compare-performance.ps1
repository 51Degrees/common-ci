param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    [Parameter(Mandatory=$true)]
    [hashtable[]]$Options,
    [string]$RunId = '0',
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

if ($env:CI -ne "true") {
    # The REST API cannot be used while the workflow is running. So in CI,
    # a GitHub Actions step is used instead.
    # See https://github.com/actions/upload-artifact/issues/53
    Write-Output "::group::Download Performance Artifact"
    ./steps/download-artifact.ps1 -RepoName $RepoName -OrgName $OrgName -RunId $RunId -ArtifactName "performance_results_$PullRequestId" -GitHubToken $GitHubToken
    Write-Output "::endgroup::"
}

Write-Output "::group::Compare Performance Results"
./steps/compare-performance.ps1 -RepoName $RepoName -OrgName $OrgName -RunId $RunId -PullRequestId $PullRequestId -AllOptions $Options -DryRun $DryRun
Write-Output "::endgroup::"
