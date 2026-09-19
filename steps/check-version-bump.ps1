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
history this compares against.
#>
param (
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$RepoName
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

# The highest version already tagged, which is what this repository has
# released. Read from the checkout rather than from a registry, so this works
# the same for every language and needs no package name.
Push-Location $RepoName
try {
    $tags = git tag --list
} finally {
    Pop-Location
}

$highest = $null
foreach ($tag in $tags) {
    $p = Get-Parts $tag
    if ($null -eq $p) { continue }
    if ($null -eq $highest -or
        $p.Major -gt $highest.Major -or
        ($p.Major -eq $highest.Major -and $p.Minor -gt $highest.Minor) -or
        ($p.Major -eq $highest.Major -and $p.Minor -eq $highest.Minor -and $p.Patch -gt $highest.Patch)) {
        $highest = $p
    }
}

if ($null -eq $highest) {
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
