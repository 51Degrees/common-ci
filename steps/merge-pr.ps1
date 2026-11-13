param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [int]$PullRequestId,
    # The branch the nightly merges into. A pull request into any other branch
    # is refused, so the nightly never merges into the default branch of a
    # repository that takes changes through rc, even for an id given by hand.
    [string]$Branch,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true


if ($PullRequestId -eq 0) {
    Write-Output "Not running for a PR"
    exit
}

$Pr = gh pr view -R $OrgName/$RepoName $PullRequestId --json number,headRefName,baseRefName,title | ConvertFrom-Json
$PrTitle = "#$($Pr.number) $($Pr.headRefName)->$($Pr.baseRefName): $($Pr.title)"

if ($DryRun) {
    Write-Output "Dry run - not merging"
} elseif ($Branch -and $Pr.baseRefName -cne $Branch) {
    Write-Output "::error title=Not merged::PR $PrTitle merges into '$($Pr.baseRefName)', and the nightly merges only into '$Branch'"
    exit 1
} else {
    Write-Output "Merging PR $PrTitle"
    gh api /repos/$OrgName/$RepoName/pulls/$PullRequestId/merge -X PUT -f "commit_title=Merged Pull Request '$PrTitle'" -f "merge_method=squash"
}
