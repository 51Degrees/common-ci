<#
.SYNOPSIS
Refuses a release that comes less than a week after the last one, unless an
early release has been allowed.

.DESCRIPTION
A package repository releases at most once a week. Changes collect on rc and
reach the default branch together in one release, so each package gets at
most one new version a week.

Search is as much the reason as the people who use the packages. nuget.org
asks search engines not to index a package's page while the oldest of its 20
newest versions is less than 90 days old (BlockSearchEngineIndexing in
NuGetGallery's DisplayPackageViewModel.cs). A package that releases more often
than once every four and a half days drops out of search. Weekly keeps every
package clear of that, with room for an urgent fix.

Days are whole calendar days in UTC, so a release on a Wednesday allows the
next from the following Wednesday, at any time of day.

To release early, set ALLOW_EARLY_RELEASE to 'true'. That is a decision made
for one release, as a major or minor version bump is.

The rule applies from the date in WEEKLY_RELEASES_FROM, such as 2026-11-03,
which the workflows take from the GitHub configuration variable of the same
name, the repository's own where it has one and otherwise the organisation's.
Unset, or set to a date still ahead, the check reports what it would decide
and passes, so the rule starts without a change to the code.

.PARAMETER LastRelease
When the last release went out, such as 2026-11-04T10:15:00Z. A time with no
offset is read as UTC. Empty when nothing has been released. Give this, even
when empty, or -RepoName.

.PARAMETER LastReleaseName
What the last release was, for the message, such as 'pull request #95'.

.PARAMETER RepoName
The directory the repository is checked out into, whose version tags are its
releases. Give this or -LastRelease.

.PARAMETER TagPrefix
With -RepoName, the one package whose releases count, for a repository that
tags each package '<TagPrefix>/<version>'. Without it every version tag
counts, with or without a package name, so the newest release of any package
is the last.

.PARAMETER Repository
With -RepoName, the repository on GitHub, such as 51Degrees/51degrees-cxx. A
lightweight tag has no date of its own, and the commit it points at can be a
day or more older than the release, so the release is dated by the GitHub
release made with the tag. Without this, or for a tag with no GitHub release,
the commit's date is used.

.PARAMETER HowToAllow
How to release early where this runs, ending the sentence "With it, ...".

.PARAMETER Now
The time to judge against, for tests. Defaults to now.
#>
param (
    [string]$LastRelease,
    [string]$LastReleaseName,
    [string]$RepoName,
    [string]$TagPrefix,
    [string]$Repository,
    [string]$HowToAllow = "run this again with ALLOW_EARLY_RELEASE set to 'true'.",
    [string]$Now
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$DaysBetweenReleases = 7

function ConvertTo-UtcTime ([string]$Text) {
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal
    $time = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Text,
            [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$time)) {
        throw "'$Text' is not a date and time this can read. Expected something like 2026-11-04T10:15:00Z."
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

    $pattern = $TagPrefix `
        ? "^$([regex]::Escape($TagPrefix))/v?\d+\.\d+\.\d+" `
        : '^(.+/)?v?\d+\.\d+\.\d+'

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
        if ($name -notmatch $pattern) { continue }

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

# Read first, so a value that cannot be read is reported whatever the release.
$from = $env:WEEKLY_RELEASES_FROM
if ($from) {
    try {
        $fromDay = (ConvertTo-UtcTime $from).UtcDateTime.Date
    } catch {
        throw "WEEKLY_RELEASES_FROM is '$from', which is not a date such as 2026-11-03. Correct the configuration variable of that name."
    }
    $enforced = $today -ge $fromDay
    $state = $enforced `
        ? "The weekly release rule applies from $(Format-Day $fromDay), the date in WEEKLY_RELEASES_FROM." `
        : "The weekly release rule is not enforced until $(Format-Day $fromDay), the date in WEEKLY_RELEASES_FROM."
} else {
    $enforced = $false
    $state = "The weekly release rule is not enforced, as WEEKLY_RELEASES_FROM is not set."
}
Write-Output $state

if ($null -eq $last) {
    Write-Output "Nothing has been released before, so this is the first release. Nothing to check."
    exit 0
}

$lastDay = $last.UtcDateTime.Date
$firstDay = $lastDay.AddDays($DaysBetweenReleases)
$facts = ("The last release, $LastReleaseName, was on $(Format-Day $lastDay), " +
    "so the next may go from $(Format-Day $firstDay).")

if ($today -ge $firstDay) {
    Write-Output "$facts This one is on $(Format-Day $today), so it may go."
    exit 0
}

if (-not $enforced) {
    Write-Output "::notice title=Weekly release rule not enforced::$facts Under the rule this one, on $(Format-Day $today), would be refused. $state"
    exit 0
}

if ($env:ALLOW_EARLY_RELEASE -eq 'true') {
    Write-Output "::warning title=Early release::$facts This one goes early, on $(Format-Day $today), allowed by ALLOW_EARLY_RELEASE."
    exit 0
}

Write-Output ("::error title=Released less than a week ago::$facts An early " +
    "release needs James Rosewell's permission. With it, $HowToAllow")
Write-Output ""
if ($lastDay -gt $today) {
    Write-Output ("The last release is dated after today, $(Format-Day $today), " +
        "so a clock or the date of the last release is wrong.")
    Write-Output ""
}
Write-Output ("Nothing is released. A package repository releases at most once a " +
    "week, so each package gets at most one new version a week. nuget.org asks " +
    "search engines not to index a package's page while the oldest of its 20 " +
    "newest versions is under 90 days old, so a package that releases more often " +
    "drops out of search.")
Write-Output ""
Write-Output "Without permission, run this again on or after $(Format-Day $firstDay)."
exit 1
