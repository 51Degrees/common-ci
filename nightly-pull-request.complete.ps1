param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    # The branch the nightly merges into, passed on to merge-pr.ps1.
    [string]$Branch,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

./steps/merge-pr.ps1 -RepoName $RepoName -OrgName $OrgName -PullRequestId $PullRequestId -Branch $Branch -DryRun $DryRun
