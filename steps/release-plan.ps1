# Dot-sourced by the scripts of a repository that gives each package its own
# version. Reads the packages from the repository's ci/packages.json and works
# out which of them a publish releases, at which version. A package is
# released when a file that counts under its folders changed since its last
# '<package>/<version>' tag, or when a package it depends on is released, and
# only the patch number moves.
#
# A Go module's tags are '<package>/v<version>', and version-tags.ps1 says
# which tags count.
#
# REPO_SCRIPTS.md describes the fields of ci/packages.json, under "Packages",
# and the optional ci/release-plan-filter.ps1, under "Release Plan Filter".

. (Join-Path $PSScriptRoot 'version-tags.ps1')

# The files whose changes do not release a package, being documentation,
# tests, examples and LICENSE files wherever they sit and whatever their case,
# unless the package sets IgnoreDefaults to false. These are git glob
# pathspecs from the repository root, where '**/' matches any number of
# folders, none included.
$ReleasePlanDefaultIgnore = @(
    '**/*.md'
    '**/docs/**'
    '**/tests/**'
    '**/test/**'
    '**/examples/**'
    '**/LICENSE*'
)

# The entries of the repository's ci/packages.json.
function Get-Packages([string]$RepoPath) {
    return Get-Content -Raw (Join-Path $RepoPath 'ci/packages.json') |
        ConvertFrom-Json
}

# The folders whose changes count as a change to the package: its own folder,
# and any folder it takes files from at build time, such as a submodule it
# vendors.
function Get-PackagePaths($Package) {
    $paths = @($Package.Path)
    if ($Package.ExtraPaths) {
        $paths += $Package.ExtraPaths
    }
    return $paths
}

function Test-PathUnder([string]$Path, [string]$Folder) {
    return $Path -eq $Folder -or $Path.StartsWith("$Folder/")
}

# The pathspecs that leave out of a package's changes the files its Ignore
# globs match and, unless IgnoreDefaults is false, the default set.
# PowerShell on Linux and macOS replaces a native command's argument that
# holds a '*' with the files it matches, if any. Each of these starts with
# ':(', which no file in a checkout starts with, so git receives it as written.
function Get-PackageExcludes($Package) {
    $defaults = $Package.IgnoreDefaults
    if ($null -ne $defaults -and $defaults -isnot [bool]) {
        throw "$($Package.Name) gives IgnoreDefaults as '$defaults', where " +
            "packages.json must give true or false."
    }
    $excludes = @($Package.Ignore | Where-Object { $_ } |
        ForEach-Object { ":(exclude,glob)$_" })
    if ($defaults -ne $false) {
        # The defaults ignore case, as one language names a folder Tests or
        # Examples where another names it tests or examples.
        $excludes = @($ReleasePlanDefaultIgnore |
            ForEach-Object { ":(exclude,glob,icase)$_" }) + $excludes
    }
    return $excludes
}

# The files under the package's folders that changed since the given tag, as
# paths from the repository root, apart from those it ignores.
function Get-ChangedFiles([string]$RepoPath, $Package, [string]$From) {
    # A failure is reported below, naming the package, whatever the caller's
    # preference. Set for this function only.
    $PSNativeCommandUseErrorActionPreference = $false
    $pathspecs = @(Get-PackagePaths $Package) + @(Get-PackageExcludes $Package)
    $files = @(& git -C $RepoPath -c core.quotePath=false diff --name-only $From HEAD -- $pathspecs)
    if ($LASTEXITCODE -ne 0) {
        throw "git could not list the changes to $($Package.Name) since $From."
    }
    return $files
}

# The files that count among a package's changed files. A repository's
# ci/release-plan-filter.ps1 decides when there is one, and otherwise every
# file counts. A path the filter returns that it was not given stops the
# plan, because a filter that rewrote a path would otherwise release a
# package on a file that never changed.
function Select-CountedFiles([string]$RepoPath, $Package, [string]$From,
        [string[]]$Files) {
    $filter = Join-Path $RepoPath 'ci/release-plan-filter.ps1'
    if ($Files.Count -eq 0 -or (Test-Path $filter -PathType Leaf) -eq $false) {
        return $Files
    }
    $filter = (Resolve-Path $filter).ProviderPath
    $kept = @(& $filter -RepoPath $RepoPath -Package $Package -From $From `
        -Files $Files | Where-Object { $_ })
    foreach ($file in $kept) {
        if ($Files -cnotcontains $file) {
            throw "ci/release-plan-filter.ps1 returned '$file' for " +
                "$($Package.Name), which is not one of the files it was given."
        }
    }
    return $kept
}

# The names of the given packages and of every package that depends on one of
# them, directly or through another.
function Get-DependentClosure($Packages, [string[]]$Names) {
    $closure = [Collections.Generic.HashSet[string]]::new()
    foreach ($name in @($Names | Where-Object { $_ })) {
        $null = $closure.Add($name)
    }
    $grew = $true
    while ($grew -eq $true) {
        $grew = $false
        foreach ($package in $Packages) {
            if ($closure.Contains($package.Name) -eq $true) {
                continue
            }
            foreach ($dependency in $package.DependsOn) {
                if ($closure.Contains($dependency) -eq $true) {
                    $null = $closure.Add($package.Name)
                    $grew = $true
                    break
                }
            }
        }
    }
    return @($closure)
}

# The named packages, each after every package it depends on, so a release
# never publishes a package before the version it requires exists.
function Sort-ByDependency($Packages, [string[]]$Names) {
    $remaining = [Collections.Generic.List[string]]::new([string[]]@($Names))
    $sorted = [Collections.Generic.List[string]]::new()
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $name = $_
            $package = $Packages | Where-Object { $_.Name -eq $name }
            @($package.DependsOn | Where-Object {
                $remaining.Contains($_) -eq $true
            }).Count -eq 0
        } | Sort-Object)
        if ($ready.Count -eq 0) {
            throw "packages.json has a dependency cycle among: $($remaining -join ', ')"
        }
        foreach ($name in $ready) {
            $sorted.Add($name)
            $null = $remaining.Remove($name)
        }
    }
    return @($sorted)
}

# The package's released versions, read from its tags, highest last.
function Get-ReleasedVersions([string]$RepoPath, [string]$Name,
        [switch]$AtHead) {
    return @(Get-VersionTags $RepoPath -Prefix $Name -AtHead:$AtHead |
        ForEach-Object Version)
}

# What a publish of HEAD releases: one entry per package, in the order to
# publish them, each with the version it is released at and why.
#
# A package already tagged at HEAD was released from this commit, so it is
# left out, which makes a second publish of the same commit release nothing.
# A package with no tag has never been released and starts at its
# FirstVersion. A package that is not published is never in the plan, so a
# change to it is tested but releases nothing.
function Get-ReleasePlan([string]$RepoPath, $Packages = $null) {
    if ($null -eq $Packages) {
        $Packages = Get-Packages $RepoPath
    }
    $published = @($Packages | Where-Object { $_.Publish -eq $true })

    $previous = @{}
    $reasons = @{}
    foreach ($package in $published) {
        $atHead = Get-ReleasedVersions $RepoPath $package.Name -AtHead
        if ($atHead.Count -gt 0) {
            continue
        }
        $released = @(Get-VersionTags $RepoPath -Prefix $package.Name)
        if ($released.Count -eq 0) {
            if ([string]::IsNullOrEmpty($package.FirstVersion) -eq $true) {
                throw "$($package.Name) has never been released and " +
                    "packages.json gives it no FirstVersion."
            }
            $previous[$package.Name] = $null
            $reasons[$package.Name] = 'first release'
            continue
        }
        $last = $released[-1].Version
        $previous[$package.Name] = $last
        $tag = $released[-1].Tag
        $files = @(Get-ChangedFiles $RepoPath $package $tag)
        $counted = @(Select-CountedFiles $RepoPath $package $tag $files)
        if ($counted.Count -gt 0) {
            $noun = 'files'
            if ($counted.Count -eq 1) {
                $noun = 'file'
            }
            $reasons[$package.Name] =
                "changed since $last ($($counted.Count) $noun)"
        }
        # A filter may leave an exit code that was an answer, such as the 1
        # of 'git diff --quiet', which must not read as a failure to the
        # script that called this.
        $global:LASTEXITCODE = 0
    }

    # A dependent is released with its dependency, as long as it was not
    # already released from this commit.
    $candidates = @($published.Name | Where-Object {
        $previous.ContainsKey($_) -eq $true
    })
    $changed = @($reasons.Keys)
    $toRelease = @(Get-DependentClosure $published $changed | Where-Object {
        $candidates -contains $_
    })

    foreach ($name in (Sort-ByDependency $published $toRelease)) {
        $package = $published | Where-Object { $_.Name -eq $name }
        $last = $previous[$name]
        if ($null -eq $last) {
            $version = $package.FirstVersion
        } else {
            $version = "$($last.Major).$($last.Minor).$($last.Build + 1)"
        }
        $reason = $reasons[$name]
        if ($null -eq $reason) {
            $reason = 'a package it depends on is released'
        }
        [pscustomobject]@{
            Name = $name
            Path = $package.Path
            Version = $version
            Previous = $last
            Reason = $reason
        }
    }
}

# The version of every published package once HEAD is released, in the order
# of the package list, as an ordered dictionary from each package's name to an
# entry with:
#   Name      the package's name
#   Path      its folder
#   Version   its version in the release plan, or its last release when the
#             plan leaves it out
#   Previous  its last release, or $null before its first
#   Release   whether the plan releases it
#   Reason    why it is released, or that it is unchanged
# $Packages defaults to ci/packages.json and $Plan to its release plan. A
# package that has never been released and is not in the plan stops it. The
# values are every published package, so they are not a plan for the -Plan of
# check-version-bump.ps1 or check-release-interval.ps1, which would refuse a
# package released less than a week ago that this release leaves alone.
function Get-PackageVersions([string]$RepoPath, $Packages = $null,
        $Plan = $null) {
    if ($null -eq $Packages) {
        $Packages = Get-Packages $RepoPath
    }
    if ($null -eq $Plan) {
        $Plan = @(Get-ReleasePlan $RepoPath $Packages)
    }
    $versions = [ordered]@{}
    foreach ($package in @($Packages | Where-Object { $_.Publish -eq $true })) {
        $release = $Plan | Where-Object { $_.Name -eq $package.Name }
        if ($null -ne $release) {
            $version = $release.Version
            $previous = $release.Previous
            $reason = $release.Reason
        } else {
            $previous = @(Get-ReleasedVersions $RepoPath $package.Name)[-1]
            if ($null -eq $previous) {
                throw "$($package.Name) has never been released and is not " +
                    "in the release plan."
            }
            $version = "$previous"
            $reason = "unchanged since $previous"
        }
        $versions[$package.Name] = [pscustomobject]@{
            Name = $package.Name
            Path = $package.Path
            Version = $version
            Previous = $previous
            Release = $null -ne $release
            Reason = $reason
        }
    }
    return $versions
}
