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
    # When no pull request is eligible, build the branch itself, as pull
    # request 0. A run started by hand can leave that to the nightly.
    [bool]$BuildWithoutPullRequests = $true
)
$ErrorActionPreference = "Stop"

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

# Where the repository takes changes through rc, the pull requests built and
# merged are the ones into rc, never the ones into the default branch.
$Branch = ./steps/get-target-branch.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "Pull requests into '$Branch' are built and merged"
"branch=$Branch" | Out-File $GitHubOutput -Append

# If the list of pull requests is provided as a CI parameter - output it and exit early.
# An environment variable is used instead of a parameter to avoid arbitrary code injection.
if ($env:PULL_REQUEST_IDS) {
    Write-Output "Pull request ids are: $env:PULL_REQUEST_IDS"
    "pull_request_ids=[$env:PULL_REQUEST_IDS]" | Out-File $GitHubOutput -Append
    exit
}

Write-Output "::group::Get Pull Requests"
./steps/get-pull-requests.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -SetVariable PullRequestIds
if (!$BuildWithoutPullRequests -and "$PullRequestIds" -eq '0') {
    Write-Output "No pull request is eligible, so nothing is built"
    $PullRequestIds = @()
}
Write-Output "pull_request_ids=[$($PullRequestIds -Join ',')]" | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"
