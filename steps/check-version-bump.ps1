<#
.SYNOPSIS
Refuses a publish whose version moves the major or minor place, unless
somebody has said so deliberately.

.DESCRIPTION
A version can reach a publish by more than one route. A '+semver' directive in
a commit message, a tag pushed by hand, a version committed in a file, or a
workflow dispatched with a version typed into it. Gating any one of those
leaves the others open.

The publish is where every route meets, so the check belongs here. Whatever
produced the version, this compares it with the highest version this
repository has already released and refuses a move in the major or minor
place.

Why it matters enough to stop a build. The 51Degrees documentation is
versioned, so a minor bump means a new documentation version. A published
version number can never be reclaimed: NuGet cannot delete, crates.io cannot
unpublish, and PyPI burns the number even when a release is deleted. And
callers on the previous line do not receive the release, so a fix published
this way does not reach them.

On 18 September 2026 one directive in one commit took sixteen NuGet packages,
three npm packages, five PyPI projects and three crates to 4.6 overnight, and
withdrawing them took a day and could not be completed.

To publish a bump deliberately, set ALLOW_VERSION_BUMP to 'true' in the
workflow run. That is a decision someone makes with their name on it rather
than something a commit message does quietly.

.PARAMETER Version
The version about to be published, such as 4.5.110.

.PARAMETER RepoName
The directory the repository is checked out into, whose tags are the release
history this compares against. Give this or -ReleasedVersion.

.PARAMETER ReleasedVersion
The highest version already released, for a repository whose tags are not its
release history. Some repositories keep the version in a manifest and publish
without tagging, so there is nothing here to read and the check would pass
everything. Whoever calls this knows where that number lives, for example the
registry the package is published to, so they pass it in. Give this or
-RepoName.

.PARAMETER TagPrefix
With -RepoName, the package whose release history to read, for a repository
that releases several packages each with its own version. Only tags of the
form '<TagPrefix>/<version>' count, so one package is compared with its own
releases and not with the highest version of any package in the repository.
Without it every plain version tag counts, as before.
#>
param (
    [Parameter(Mandatory)][string]$Version,
    [string]$RepoName,
    [string]$ReleasedVersion,
    [string]$TagPrefix
)
$ErrorActionPreference = "Stop"

function Get-Parts ([string]$v) {
    $m = [regex]::Match($v, '^v?(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{
        Major = [int]$m.Groups[1].Value
        Minor = [int]$m.Groups[2].Value
        Patch = [int]$m.Groups[3].Value
    }
}

$next = Get-Parts $Version
if ($null -eq $next) {
    throw "'$Version' is not a version this can check. Expected something like 4.5.110."
}

if ($ReleasedVersion) {
    # Told what has been released, because this repository's tags are not its
    # release history.
    $highest = Get-Parts $ReleasedVersion
    if ($null -eq $highest) {
        throw "'$ReleasedVersion' is not a version this can check. Expected something like 4.5.110."
    }
}
elseif ($RepoName) {
    # The highest version already tagged, which is what this repository has
    # released. Read from the checkout rather than from a registry, so this
    # works the same for every language and needs no package name.
    Push-Location $RepoName
    try {
        $tags = git tag --list
    } finally {
        Pop-Location
    }

    $highest = $null
    foreach ($tag in $tags) {
        $tagVersion = $tag
        if ($TagPrefix) {
            if ($tag.StartsWith("$TagPrefix/") -eq $false) { continue }
            $tagVersion = $tag.Substring($TagPrefix.Length + 1)
        }
        $p = Get-Parts $tagVersion
        if ($null -eq $p) { continue }
        if ($null -eq $highest -or
            $p.Major -gt $highest.Major -or
            ($p.Major -eq $highest.Major -and $p.Minor -gt $highest.Minor) -or
            ($p.Major -eq $highest.Major -and $p.Minor -eq $highest.Minor -and $p.Patch -gt $highest.Patch)) {
            $highest = $p
        }
    }
}
else {
    throw "Give -RepoName, whose tags are the release history, or -ReleasedVersion where they are not."
}

if ($null -eq $highest) {
    # A repository that has never released has no tags, and GitVersion then
    # answers 0.0.1 rather than failing. Nothing else stops that number, so the
    # first publish would release it: this is how fiftyone_ipintelligence_cloud
    # 0.0.1 reached PyPI on 28 October 2026, a number PyPI never gives back. No
    # public 51Degrees package starts on a 0.x line, so a 0.x first release is
    # never intended. A repository already releasing on 0.x has tags, and so
    # never reaches this point. See common-ci#251.
    if ($next.Major -eq 0) {
        Write-Output ("::error title=First version refused::This would be the " +
            "first release, at $Version. No public 51Degrees package starts on a " +
            "0.x line, so this is the version GitVersion gives a repository with " +
            "no tags, not a chosen one.")
        Write-Output ""
        Write-Output ("Nothing is published. Decide the first version, then tag " +
            "main with the version the release should follow on from, and run " +
            "the workflow again.")
        exit 1
    }
    Write-Output "No released version to compare with, so $Version is the first. Nothing to check."
    exit 0
}

$released = "$($highest.Major).$($highest.Minor).$($highest.Patch)"
$place = $null
if ($next.Major -gt $highest.Major) { $place = "major" }
elseif ($next.Major -eq $highest.Major -and $next.Minor -gt $highest.Minor) { $place = "minor" }

if ($null -eq $place) {
    Write-Output "Publishing $Version, against $released already released. The patch place, which needs no agreement."
    exit 0
}

if ($env:ALLOW_VERSION_BUMP -eq 'true') {
    Write-Output "Publishing $Version, against $released already released. That moves the $place place, allowed by ALLOW_VERSION_BUMP."
    exit 0
}

Write-Output "::error title=Version bump refused::This publish would release $Version, against $released already released. That moves the $place place."
Write-Output ""
Write-Output "Nothing is published. To do this deliberately, run the workflow again with ALLOW_VERSION_BUMP set to 'true'."
Write-Output ""
Write-Output "Before you do, what a $place bump costs:"
Write-Output "  * The 51Degrees documentation is versioned, so this means a new documentation version."
Write-Output "  * The number can never be reclaimed. NuGet cannot delete, crates.io cannot unpublish, and PyPI burns the number even when a release is deleted."
Write-Output "  * Callers on $($highest.Major).$($highest.Minor) do not receive it, so a fix released this way does not reach them."
Write-Output ""
Write-Output "If the bump was not intended, find what asked for it: a '+semver' directive in a commit message, a tag pushed by hand, or a version committed in a file."
exit 1
