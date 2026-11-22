param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [int]$PullRequestId,
    [string]$Branch = "main",
    [string]$SetVariable = "PullRequestSha",
    # The head commit the pull request was selected at. When given, only that
    # commit is built: if the pull request has moved since, nothing is.
    [string]$HeadSha = ""
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Entering $RepoName"
Push-Location $RepoName
try {
    if ($PullRequestId -eq 0) {
        Write-Output "Not running for a PR"
        exit
    }

    $PrTitle = gh pr view $PullRequestId --json number,headRefName,baseRefName,title -t '#{{.number}} {{.headRefName}}->{{.baseRefName}} : {{.title}}'

    Write-Output "Checking out PR '$PrTitle'"
    gh pr checkout --force --recurse-submodules $PullRequestId

    if ($HeadSha) {
        $CheckedOut = git rev-parse HEAD
        if ($CheckedOut -ne $HeadSha) {
            throw "PR #$PullRequestId has moved since it was selected: its head is $CheckedOut, not $HeadSha, so it is not built"
        }
    }

    Write-Output "Merging in any changes from $Branch"
    git merge origin/$Branch

    # Submodules stay at pre-merge commits; check out what the merge recorded.
    git submodule sync --recursive
    git submodule update --init --recursive

    $Sha = if ($HeadSha) { $HeadSha } else { gh pr view $PullRequestId --json headRefOid --jq '.headRefOid' }
    Write-Output "Setting '$SetVariable' to '$Sha'"
    Set-Variable -Scope 1 -Name $SetVariable -Value $Sha

} finally {
    Write-Output "Leaving $RepoName"
    Pop-Location
}
