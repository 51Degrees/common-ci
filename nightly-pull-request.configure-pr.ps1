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
    [string]$PullRequestId
)
$ErrorActionPreference = "Stop"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Checkout PR"
./steps/checkout-pr.ps1 -RepoName $RepoName -Branch $Branch -PullRequestId $PullRequestId
Write-Output "::endgroup::"

Write-Output "::group::Get Build Options"
$Options = Get-Content $RepoName/ci/options.json -Raw
$Options = $Options -replace "`r?`n", ""
Write-Output $Options
Write-Output options=$Options | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"
