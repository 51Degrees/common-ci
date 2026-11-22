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

# Each pull request comes with the head commit it was selected at, which the
# build and the merge use. Numbers given as a CI parameter are checked the same
# way. They come through an environment variable rather than a parameter.
Write-Output "::group::Get Pull Requests"
./steps/get-pull-requests.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -Ids "$env:PULL_REQUEST_IDS" -SetVariable PullRequests
if (!$BuildWithoutPullRequests -and $PullRequests.Count -eq 1 -and $PullRequests[0].id -eq 0) {
    Write-Output "No pull request is eligible, so nothing is built"
    $PullRequests = @()
}
Write-Output "pull_requests=$(ConvertTo-Json -InputObject @($PullRequests) -Compress -AsArray)" | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"
