<#
.SYNOPSIS
Refuses a pull request from rc into the default branch that comes less than a
week after the last one merged, unless it carries the early release label.

.DESCRIPTION
A pull request from rc into the default branch is a release, so the last
release is the one of those merged most recently. check-release-interval.ps1
makes the decision and says why.

The label is read from GitHub when this runs rather than from the event,
because a re-run of the check reuses the event of the first run. Adding a
label does not run the check again, so the refusal says to re-run it.

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
$last = $null
foreach ($line in $closed) {
    $number, $mergedAt = $line -split "`t"
    if (-not $mergedAt -or [int]$number -eq $PullRequest) { continue }
    $time = [DateTimeOffset]::Parse($mergedAt,
        [Globalization.CultureInfo]::InvariantCulture)
    if ($null -eq $last -or $time -gt $last.Time) {
        $last = [pscustomobject]@{ Number = $number; Time = $time }
    }
}

$rerun = $RunUrl ? "re-run this check from $RunUrl" : 're-run this check'
$arguments = @{
    HowToAllow = ("add the label '$Label' to this pull request, then " +
        "$rerun, as adding a label does not run it.")
}
if ($last) {
    $arguments.LastRelease = $last.Time.ToString('o')
    $arguments.LastReleaseName = "pull request #$($last.Number)"
}
if ($Now) { $arguments.Now = $Now }

& "$PSScriptRoot/check-release-interval.ps1" @arguments
exit $LASTEXITCODE
