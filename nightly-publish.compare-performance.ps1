param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$GitHubToken,
    [Parameter(Mandatory)][string]$GitHubOutput,
    [Parameter(Mandatory)][hashtable[]]$Options,
    [string]$Branch = "main",
    [string]$RunId = '0',
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Compare Performance Results"
./steps/compare-performance.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -AllOptions $Options -DryRun $DryRun -Publish
Write-Output "::endgroup::"
