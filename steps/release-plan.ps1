# Dot-sourced by the scripts of a repository that gives each package its own
# version. Reads the packages from the repository's ci/packages.json and works
# out which of them a publish releases, at which version.
#
# Each package is tagged '<package>/<version>'. A package is released when a
# file under its folders changed since its last tag, or when a package it
# depends on is released, because its requirement on that package moves. Only
# the patch number moves.
#
# Each entry in ci/packages.json has:
#   Name          the package's name, which its tags start with
#   Path          its folder, from the repository root
#   ExtraPaths    other folders it takes files from at build time, optional
#   DependsOn     the names of the packages it requires
#   Publish       false for a package that is never released, such as examples
#   FirstVersion  the version of its first release, for a package with no tag

# Reads ci/packages.json. Kept as a function so the tests can give their own
# list.
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

# The parts of a version such as 4.5.38, or $null for anything else.
function ConvertTo-VersionParts([string]$Text) {
    $match = [regex]::Match($Text, '^(\d+)\.(\d+)\.(\d+)$')
    if ($match.Success -eq $false) {
        return $null
    }
    return [version]::new([int]$match.Groups[1].Value,
        [int]$match.Groups[2].Value, [int]$match.Groups[3].Value)
}

# The package's released versions, read from its '<package>/<version>' tags,
# highest last. The '/' after the name keeps a package from reading the tags
# of another whose name starts with its own.
function Get-ReleasedVersions([string]$RepoPath, [string]$Name,
        [switch]$AtHead) {
    # Tags are found by prefix, not with a 'name/*' pattern, because PowerShell
    # on Linux and macOS expands a '*' in an argument to a native command into
    # matching files, and would give git file names.
    $arguments = @('-C', $RepoPath, 'for-each-ref',
        '--format=%(refname:strip=2)', "refs/tags/$Name/")
    if ($AtHead -eq $true) {
        $arguments += @('--points-at', 'HEAD')
    }
    $versions = foreach ($tag in (& git @arguments)) {
        ConvertTo-VersionParts $tag.Substring($Name.Length + 1)
    }
    return @($versions | Where-Object { $null -ne $_ } | Sort-Object)
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
    # 'git diff --quiet' exits 1 to say a package changed, which is an answer
    # rather than a failure, so a caller that stops on a failing native command
    # must not stop here. Set for this function only.
    $PSNativeCommandUseErrorActionPreference = $false
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
        $released = Get-ReleasedVersions $RepoPath $package.Name
        if ($released.Count -eq 0) {
            if ([string]::IsNullOrEmpty($package.FirstVersion) -eq $true) {
                throw "$($package.Name) has never been released and " +
                    "packages.json gives it no FirstVersion."
            }
            $previous[$package.Name] = $null
            $reasons[$package.Name] = 'first release'
            continue
        }
        $last = $released[-1]
        $previous[$package.Name] = $last
        $tag = "$($package.Name)/$last"
        & git -C $RepoPath diff --quiet $tag HEAD -- (Get-PackagePaths $package)
        if ($LASTEXITCODE -eq 1) {
            $reasons[$package.Name] = "changed since $last"
        }
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
