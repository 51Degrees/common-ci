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

This check guards against one directive in one commit moving every package a
repository publishes to a new minor version in a single run, in every
registry at once.

To publish a bump deliberately, set ALLOW_VERSION_BUMP to 'true' in the
workflow run. That is a decision someone makes with their name on it rather
than something a commit message does quietly.

.PARAMETER Version
The version about to be published, such as 4.5.110. Give this or -Plan.

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
that releases several packages each with its own version. Only the package's
own tags, '<TagPrefix>/<version>' or '<TagPrefix>/v<version>', count, so one
package is compared with its own releases and not with the highest version of
any package in the repository. Without it only the tags with no package
prefix count. version-tags.ps1 says which tags are releases.

.PARAMETER Plan
With -RepoName, the release plan, being the packages about to be published,
for a repository that gives each package its own version, such as
Get-ReleasePlan's output. Give the plan and not every package, because
check-release-interval.ps1 takes the same plan and would refuse a package
released less than a week ago that this publish does not release. Each entry
needs a Name, which its tags start with, and a Version. Each package is
checked as -Version with -TagPrefix checks one, and the publish is refused
when any package is. A plan with nothing in it passes.

.PARAMETER RegistryVersionScript
With -Plan only, a script giving the highest version a package's registry has
released, which the package is also checked against. It is called as
  & <script> -RepoName <path> -Package <entry of the plan>
and returns that version, or nothing when the registry has none. A package
with no tag of its own that the registry has not released either is refused,
because nothing has decided where its versions start.
#>
# An unknown parameter stops the check, so a misspelt name cannot leave a
# package checked against the wrong tags.
[CmdletBinding()]
param (
    [string]$Version,
    [string]$RepoName,
    [string]$ReleasedVersion,
    [string]$TagPrefix,
    [object[]]$Plan,
    [string]$RegistryVersionScript
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'version-tags.ps1')

if ($RegistryVersionScript -and
        -not $PSBoundParameters.ContainsKey('Plan')) {
    throw "Give -RegistryVersionScript only with -Plan."
}

# Each package of a plan is checked by running this script again for it, so
# it is judged exactly as a single package is.
if ($PSBoundParameters.ContainsKey('Plan')) {
    if ($Version -or $ReleasedVersion -or $TagPrefix -or -not $RepoName) {
        throw "Give -Plan with -RepoName, and without -Version, " +
            "-ReleasedVersion or -TagPrefix."
    }
    $packages = @($Plan | Where-Object { $null -ne $_ })
    if ($packages.Count -eq 0) {
        Write-Output "No package is to be published, so there is nothing to check."
        exit 0
    }
    $refused = @()
    foreach ($package in $packages) {
        if (-not $package.Name -or -not $package.Version) {
            throw "Each entry of -Plan needs a Name and a Version."
        }
        Write-Output "$($package.Name) $($package.Version), against its own tags:"
        & $PSCommandPath -Version $package.Version -RepoName $RepoName `
            -TagPrefix $package.Name
        $passed = $LASTEXITCODE -eq 0
        if ($RegistryVersionScript) {
            $released = @(& $RegistryVersionScript -RepoName $RepoName `
                -Package $package | Where-Object { $_ })
            if ($released.Count -gt 1) {
                throw "$RegistryVersionScript gave more than one version " +
                    "for $($package.Name)."
            }
            if ($released.Count -eq 1) {
                Write-Output ("$($package.Name) $($package.Version), against " +
                    "$($released[0]) in its registry:")
                & $PSCommandPath -Version $package.Version `
                    -ReleasedVersion "$($released[0])"
                $passed = $passed -and $LASTEXITCODE -eq 0
            } elseif (@(Get-VersionTags $RepoName `
                    -Prefix $package.Name).Count -eq 0) {
                # Neither a tag nor the registry says where the package's
                # versions start, and its FirstVersion is a file anyone can
                # change.
                Write-Output ("::error title=First release refused::" +
                    "$($package.Name) has no tag here and its registry has " +
                    "not released it, so nothing has decided where its " +
                    "versions start. Before its first release, tag it " +
                    "'$($package.Name)/<version>' with the version that " +
                    "release follows on from, then run the workflow again.")
                $passed = $false
            }
        }
        if ($passed -eq $false) {
            $refused += $package.Name
        }
    }
    if ($refused.Count -gt 0) {
        Write-Output ("Nothing is published, because these packages were " +
            "refused: $($refused -join ', ').")
        exit 1
    }
    exit 0
}

if (-not $Version) {
    throw "Give -Version, the version about to be published, or -Plan."
}

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
    $tags = @(Get-VersionTags $RepoName -Prefix $TagPrefix)
    $highest = $tags.Count -gt 0 ? (Get-Parts "$($tags[-1].Version)") : $null
}
else {
    throw "Give -RepoName, whose tags are the release history, or -ReleasedVersion where they are not."
}

if ($null -eq $highest) {
    # A branch with no release tag has never released, and GitVersion then
    # answers 0.0.1 rather than failing. So a first release from such a branch
    # is refused, whatever its version, and someone decides the number by
    # tagging. The version itself is not judged, because a package may rightly
    # start on 0.x. A branch that has release tags, but none for this package,
    # is a repository releasing a new package beside others, and its number
    # was chosen there. Only -RepoName reaches here, because -ReleasedVersion
    # always sets $highest.
    if (@(Get-VersionTags $RepoName -AnyPrefix -Merged).Count -eq 0) {
        Write-Output ("::error title=First release refused::This branch has " +
            "no release tag, so nothing has decided where its versions start, " +
            "and $Version would be published as the first. With no tags " +
            "GitVersion answers 0.0.1.")
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
