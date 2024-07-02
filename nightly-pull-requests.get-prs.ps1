param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput
)
$ErrorActionPreference = "Stop"

# If the list of pull requests is provided as a CI parameter - output it and exit early.
# An environment variable is used instead of a parameter to avoid arbitrary code injection.
if ($env:PULL_REQUEST_IDS) {
    Write-Output "Pull request ids are: $env:PULL_REQUEST_IDS"
    "pull_request_ids=[$env:PULL_REQUEST_IDS]" | Out-File $GitHubOutput -Append
    exit
}

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

Write-Output "::group::Get Pull Requests"
./steps/get-pull-requests.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -SetVariable PullRequestIds
Write-Output "pull_request_ids=[$($PullRequestIds -Join ',')]" | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"
