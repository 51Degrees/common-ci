<#
.SYNOPSIS
Refuses a second release in a calendar month, unless that release has been
given permission.

.DESCRIPTION
A package repository releases at most once a calendar month, as
CONTRIBUTING.md explains under "Releasing at most once a month". Months are
calendar months in UTC, so the next release may go from the first day of the
month after the last release.

The rule began on 19 November 2026, with the 4.6 releases. A release before
that day does not count, so the first release on or after it may go whenever
the one before it went.

ALLOW_EARLY_RELEASE set to 'true' allows one more release in the month. It
is set for one release only, from the label on that release's pull request
or from the input of that one run of the publish.

.PARAMETER LastRelease
When the last release went out, such as 2026-12-04T10:15:00Z. A time with no
offset is read as UTC. Empty when nothing has been released. Give this, even
when empty, or -RepoName.

.PARAMETER LastReleaseName
What the last release was, for the message, such as 'pull request #95'.

.PARAMETER RepoName
The directory the repository is checked out into, whose version tags are its
releases. Give this or -LastRelease.

.PARAMETER TagPrefix
With -RepoName, the one package whose releases count, for a repository that
tags each package '<TagPrefix>/<version>' or '<TagPrefix>/v<version>'.
Without it every version tag counts, with or without a package name, so the
newest release of any package is the last. version-tags.ps1 says which tags
are releases.

.PARAMETER Repository
With -RepoName, the repository on GitHub, such as 51Degrees/51degrees-cxx. A
lightweight tag has no date of its own, and the commit it points at can be a
day or more older than the release, so the release is dated by the GitHub
release made with the tag. Without this, or for a tag with no GitHub release,
the commit's date is used.

.PARAMETER HowToAllow
How to give permission for this one release where this runs, ending the
sentence "With it, ...".

.PARAMETER Now
The time to judge against, for tests. Defaults to now.

.PARAMETER Plan
With -RepoName, the release plan, being the packages about to be published,
for a repository that gives each package its own version, such as
Get-ReleasePlan's output. Give the plan and not every package, because a
package released this month that this release leaves alone would be refused.
Each entry needs a Name, which its tags start with. Each package is checked
as -TagPrefix checks one, and the release is refused when any package is. A
plan with nothing in it passes. It is the last parameter, so that the others
keep their positions.
#>
# An unknown parameter stops the check, so a misspelt name cannot leave a
# package checked against the wrong tags.
[CmdletBinding()]
param (
    [string]$LastRelease,
    [string]$LastReleaseName,
    [string]$RepoName,
    [string]$TagPrefix,
    [string]$Repository,
    [string]$HowToAllow = "run this again with ALLOW_EARLY_RELEASE set to 'true'.",
    [string]$Now,
    [object[]]$Plan
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'version-tags.ps1')

# Each package of a plan is checked by running this script again for it, so
# it is judged exactly as a single package is.
if ($PSBoundParameters.ContainsKey('Plan')) {
    if ($TagPrefix -or $PSBoundParameters.ContainsKey('LastRelease') -or
            -not $RepoName) {
        throw "Give -Plan with -RepoName, and without -TagPrefix or -LastRelease."
    }
    $packages = @($Plan | Where-Object { $null -ne $_ })
    if ($packages.Count -eq 0) {
        Write-Output "No package is to be published, so there is nothing to check."
        exit 0
    }
    $arguments = @{ RepoName = $RepoName }
    if ($Repository) { $arguments.Repository = $Repository }
    if ($HowToAllow) { $arguments.HowToAllow = $HowToAllow }
    if ($Now) { $arguments.Now = $Now }
    $refused = @()
    foreach ($package in $packages) {
        if (-not $package.Name) {
            throw "Each entry of -Plan needs a Name."
        }
        Write-Output "$($package.Name):"
        & $PSCommandPath @arguments -TagPrefix $package.Name
        if ($LASTEXITCODE -ne 0) {
            $refused += $package.Name
        }
    }
    if ($refused.Count -gt 0) {
        Write-Output ("Nothing is released, because these packages were " +
            "already released this calendar month: $($refused -join ', ').")
        exit 1
    }
    exit 0
}

# The day the rule of one release a calendar month began, with the 4.6
# releases. A release before it does not count.
$RuleBegan = [DateTime]::new(2026, 11, 19, 0, 0, 0, [DateTimeKind]::Utc)

function ConvertTo-UtcTime ([string]$Text) {
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal
    $time = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Text,
            [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$time)) {
        throw "'$Text' is not a date and time this can read. Expected something like 2026-12-04T10:15:00Z."
    }
    return $time.ToUniversalTime()
}

function Format-Day ([DateTime]$Day) {
    return $Day.ToString('d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
}

# The newest release among the version tags of a checkout, or $null when there
# is none.
function Get-LastTaggedRelease {
    param ([string]$RepoName, [string]$TagPrefix, [string]$Repository)

    $published = @{}
    if ($Repository) {
        # The newest hundred releases. An older release cannot be the last.
        $releases = gh release list -R $Repository --exclude-drafts `
            --limit 100 --json tagName,publishedAt `
            --jq '.[] | [.tagName, (.publishedAt // "")] | @tsv'
        foreach ($line in $releases) {
            $tag, $date = $line -split "`t"
            if ($date) { $published[$tag] = $date }
        }
    }

    $format = '%(refname:strip=2)%09%(objecttype)%09%(taggerdate:iso-strict)' +
        '%09%(committerdate:iso-strict)%09%(*committerdate:iso-strict)'
    $last = $null
    foreach ($line in (git -C $RepoName for-each-ref refs/tags "--format=$format")) {
        $name, $type, $taggerDate, $commitDate, $targetDate = $line -split "`t"
        if ($null -eq (ConvertFrom-VersionTag $name $TagPrefix -AnyPrefix)) { continue }

        # An annotated tag records when it was made. A lightweight one does
        # not, so its GitHub release dates it, and failing that its commit.
        if ($type -eq 'tag' -and $taggerDate) {
            $date = $taggerDate
            $source = 'its tag'
        } elseif ($published.ContainsKey($name)) {
            $date = $published[$name]
            $source = 'its GitHub release'
        } else {
            $date = $commitDate ? $commitDate : $targetDate
            $source = 'its commit, as it has no GitHub release'
        }
        $time = ConvertTo-UtcTime $date
        if ($null -eq $last -or $time -gt $last.Time) {
            $last = [pscustomobject]@{ Name = $name; Time = $time; Source = $source }
        }
    }
    return $last
}

if ($RepoName) {
    $tagged = Get-LastTaggedRelease -RepoName $RepoName -TagPrefix $TagPrefix `
        -Repository $Repository
    if ($tagged) {
        Write-Output ("The newest release tag is $($tagged.Name), dated " +
            "$($tagged.Time.ToString('u')) by $($tagged.Source).")
        $last = $tagged.Time
        $LastReleaseName = $tagged.Name
    } else {
        $last = $null
    }
} elseif ($PSBoundParameters.ContainsKey('LastRelease')) {
    $last = $LastRelease ? (ConvertTo-UtcTime $LastRelease) : $null
    if (-not $LastReleaseName) { $LastReleaseName = 'the last release' }
} else {
    throw "Give -RepoName, whose version tags are the releases, or -LastRelease, empty when there has been none."
}

$today = ($Now ? (ConvertTo-UtcTime $Now) : [DateTimeOffset]::UtcNow).UtcDateTime.Date

if ($null -eq $last) {
    Write-Output "Nothing has been released before, so this is the first release. Nothing to check."
    exit 0
}

$lastDay = $last.UtcDateTime.Date
if ($lastDay -lt $RuleBegan) {
    Write-Output ("The last release, $LastReleaseName, was on $(Format-Day $lastDay), " +
        "before the rule of one release a calendar month began on " +
        "$(Format-Day $RuleBegan), so this one may go.")
    exit 0
}

# The first day of the calendar month after the last release.
$firstDay = [DateTime]::new($lastDay.Year, $lastDay.Month, 1, 0, 0, 0,
    [DateTimeKind]::Utc).AddMonths(1)
$facts = ("The last release, $LastReleaseName, was on $(Format-Day $lastDay), " +
    "so the next may go from $(Format-Day $firstDay).")

if ($today -ge $firstDay) {
    Write-Output "$facts This one is on $(Format-Day $today), so it may go."
    exit 0
}

if ($env:ALLOW_EARLY_RELEASE -eq 'true') {
    Write-Output ("::warning title=Extra release this month::$facts This one " +
        "goes on $(Format-Day $today), allowed for this release by ALLOW_EARLY_RELEASE.")
    exit 0
}

Write-Output ("::error title=Released already this calendar month::$facts " +
    "Another release before then needs permission for that one release. With it, $HowToAllow")
Write-Output ""
if ($lastDay -gt $today) {
    Write-Output ("The last release is dated after today, $(Format-Day $today), " +
        "so a clock or the date of the last release is wrong.")
    Write-Output ""
}
Write-Output ("Nothing is released. A package repository releases at most once a " +
    "calendar month, for the reasons in https://github.com/51Degrees/common-ci/blob/main/CONTRIBUTING.md#releasing-at-most-once-a-month")
Write-Output ""
Write-Output "Without permission, run this again on or after $(Format-Day $firstDay)."
exit 1
