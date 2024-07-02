param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [int]$PullRequestId,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true


if ($PullRequestId -eq 0) {
    Write-Output "Not running for a PR"
    exit
}

$PrTitle = gh pr view -R $OrgName/$RepoName $PullRequestId --json number,headRefName,baseRefName,title -t '#{{.number}} {{.headRefName}}->{{.baseRefName}}: {{.title}}'

if ($DryRun) {
    Write-Output "Dry run - not merging"
} else {
    Write-Output "Merging PR $PrTitle"
    gh api /repos/$OrgName/$RepoName/pulls/$PullRequestId/merge -X PUT -f "commit_title=Merged Pull Request '$PrTitle'"
}
