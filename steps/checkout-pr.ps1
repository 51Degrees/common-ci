param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [int]$PullRequestId,
    [string]$Branch = "main",
    [string]$SetVariable = "PullRequestSha"
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

    Write-Output "Merging in any changes from $Branch"
    git merge origin/$Branch

    $Sha = gh pr view $PullRequestId --json headRefOid --jq '.headRefOid'
    Write-Output "Setting '$SetVariable' to '$Sha'"
    Set-Variable -Scope 1 -Name $SetVariable -Value $Sha

} finally {
    Write-Output "Leaving $RepoName"
    Pop-Location
}
