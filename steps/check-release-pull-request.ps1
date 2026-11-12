<#
.SYNOPSIS
Refuses a pull request from rc into the default branch that comes less than a
week after the last one merged, unless it carries the early release label.

.DESCRIPTION
The last release is the pull request from rc merged most recently, and
check-release-interval.ps1 makes the decision. The label is read from GitHub
rather than from the event, because a re-run reuses the event of the first run.

.PARAMETER Repository
The repository on GitHub, such as 51Degrees/51degrees-cxx.

.PARAMETER PullRequest
The number of the pull request being checked.

.PARAMETER DefaultBranch
The repository's default branch, which rc releases into.

.PARAMETER Label
The label that allows an early release.

.PARAMETER RunUrl
The page of this run, where the check is re-run.

.PARAMETER Now
The time to judge against, for tests. Defaults to now.
#>
param (
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][int]$PullRequest,
    [Parameter(Mandatory)][string]$DefaultBranch,
    [string]$Label = 'early-release',
    [string]$RunUrl,
    [string]$Now
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$labels = @(gh api "repos/$Repository/pulls/$PullRequest" --jq '.labels[].name')
$env:ALLOW_EARLY_RELEASE = ($labels -contains $Label) ? 'true' : 'false'
if ($env:ALLOW_EARLY_RELEASE -eq 'true') {
    Write-Output "The label '$Label' is on pull request #$PullRequest."
}

# Pull requests from this repository's own rc only, as a fork's rc is not a
# release.
$owner = $Repository.Split('/')[0]
$closed = gh api ("repos/$Repository/pulls?state=closed&base=$DefaultBranch" +
    "&head=${owner}:rc&sort=updated&direction=desc&per_page=100") `
    --jq '.[] | [.number, (.merged_at // "")] | @tsv'
# GitHub gives every time in UTC ending in Z, so the times sort as text.
$last = $closed | ConvertFrom-Csv -Delimiter "`t" -Header Number, MergedAt |
    Where-Object { $_.MergedAt -and [int]$_.Number -ne $PullRequest } |
    Sort-Object MergedAt | Select-Object -Last 1

$rerun = $RunUrl ? "re-run this check from $RunUrl" : 're-run this check'
$arguments = @{
    LastRelease = ''
    HowToAllow = ("add the label '$Label' to this pull request, then " +
        "$rerun, as adding a label does not run it.")
}
if ($last) {
    $arguments.LastRelease = $last.MergedAt
    $arguments.LastReleaseName = "pull request #$($last.Number)"
}
if ($Now) { $arguments.Now = $Now }

& "$PSScriptRoot/check-release-interval.ps1" @arguments
exit $LASTEXITCODE
