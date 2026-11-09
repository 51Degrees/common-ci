# Tests for steps/release-plan.ps1.
#
# The selection rules are tested against a small package list written here, so
# a test states exactly which graph it relies on. The release plan reads tags
# and diffs, so those tests build a throwaway git repository.

BeforeAll {
    . (Join-Path $PSScriptRoot 'release-plan.ps1')

    # The optional fields are left off the entry unless given, as a
    # packages.json that does not use them leaves them out.
    function New-Package([string]$Name, [string]$Path,
            [string[]]$DependsOn = @(), [bool]$Publish = $true,
            [string]$FirstVersion = $null, [string[]]$ExtraPaths = $null,
            [string[]]$Ignore = $null, $IgnoreDefaults = $null) {
        $package = [pscustomobject]@{
            Name = $Name; Path = $Path
            DependsOn = $DependsOn; Publish = $Publish
            FirstVersion = $FirstVersion
        }
        if ($ExtraPaths) {
            $package | Add-Member ExtraPaths $ExtraPaths
        }
        if ($Ignore) {
            $package | Add-Member Ignore $Ignore
        }
        if ($null -ne $IgnoreDefaults) {
            $package | Add-Member IgnoreDefaults $IgnoreDefaults
        }
        return $package
    }

    # The graph with the named package replaced by the one given.
    function Set-Package($Graph, $Package) {
        return @($Graph | ForEach-Object {
            if ($_.Name -eq $Package.Name) { $Package } else { $_ }
        })
    }

    # Writes the repository's ci/release-plan-filter.ps1. It records each call
    # as a line in filter-calls.txt at the repository root, and returns the
    # files the given condition keeps.
    function Set-Filter([string]$Repo, [string]$Keep) {
        $null = New-Item -ItemType Directory -Force (Join-Path $Repo 'ci')
        Set-Content (Join-Path $Repo 'ci' 'release-plan-filter.ps1') @(
            'param([string]$RepoPath, $Package, [string]$From, [string[]]$Files)'
            'Add-Content (Join-Path $RepoPath ''filter-calls.txt'') `'
            '    "$($Package.Name) $From $($Files -join '','')"'
            "`$Files | Where-Object { $Keep }")
    }

    function Get-FilterCalls([string]$Repo) {
        $log = Join-Path $Repo 'filter-calls.txt'
        if ((Test-Path $log) -eq $false) {
            return @()
        }
        return @(Get-Content $log)
    }

    # Two pipeline packages, one device detection package on top of them, a
    # location package that is its whole product folder, a package that
    # vendors another folder, a never released package and an unpublished
    # example.
    $script:Graph = @(
        New-Package 'core' 'pipeline/core'
        New-Package 'engines' 'pipeline/engines' @('core')
        New-Package 'did' 'pipeline/did' -ExtraPaths @('pipeline/owid')
        New-Package 'dd' 'device/dd' @('engines')
        New-Package 'location' 'location' @('core')
        New-Package 'ipi' 'ipi/ipi' @('engines') -FirstVersion '4.5.0'
        New-Package 'examples' 'device/examples' @('dd') -Publish $false
    )

    # A repository with the given files committed and the given tags on that
    # commit. Further commits are made with Add-Commit.
    function New-Repo([string[]]$Files, [string[]]$Tags) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        Add-Commit $path $Files
        foreach ($tag in $Tags) {
            git -C $path tag $tag
        }
        return $path
    }

    function Add-Commit([string]$Repo, [string[]]$Files) {
        foreach ($file in $Files) {
            $full = Join-Path $Repo $file
            $null = New-Item -ItemType Directory -Force (Split-Path $full)
            Add-Content -Path $full -Value ([Guid]::NewGuid())
        }
        git -C $Repo add -A
        git -C $Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'Change'
    }

    $script:AllFiles = @(
        'pipeline/core/a.py', 'pipeline/engines/a.py', 'pipeline/did/a.py',
        'pipeline/owid/a.py', 'device/dd/a.py', 'device/examples/a.py',
        'location/setup.py', 'ipi/ipi/a.py')
    $script:AllTags = @('core/4.5.38', 'engines/4.5.38', 'did/4.5.38',
        'dd/4.5.96', 'location/4.5.4')
}

Describe 'release-plan.ps1' {

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
}

Describe 'Get-Packages' {
    It 'reads ci/packages.json' {
        $script:Repo = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Force (Join-Path $script:Repo 'ci')
        $script:Graph | ConvertTo-Json |
            Set-Content (Join-Path $script:Repo 'ci' 'packages.json')
        (Get-Packages $script:Repo).Name | Should -Be $script:Graph.Name
    }
}

Describe 'Get-DependentClosure' {
    It 'adds every package that depends on a changed one, through others' {
        $closure = Get-DependentClosure $script:Graph @('core')
        $closure | Sort-Object | Should -Be @(
            'core', 'dd', 'engines', 'examples', 'ipi', 'location')
    }

    It 'adds nothing for a package nothing depends on' {
        Get-DependentClosure $script:Graph @('did') | Should -Be @('did')
    }

    It 'is empty when given nothing' {
        @(Get-DependentClosure $script:Graph @()).Count | Should -Be 0
    }
}

Describe 'Sort-ByDependency' {
    It 'puts every package after the packages it depends on' {
        $order = Sort-ByDependency $script:Graph @('dd', 'engines', 'core')
        $order | Should -Be @('core', 'engines', 'dd')
    }

    It 'ignores dependencies that are not being sorted' {
        Sort-ByDependency $script:Graph @('dd') | Should -Be @('dd')
    }

    It 'refuses a cycle rather than looping' {
        $cycle = @(
            New-Package 'a' 'p/a' @('b')
            New-Package 'b' 'p/b' @('a'))
        { Sort-ByDependency $cycle @('a', 'b') } | Should -Throw '*cycle*'
    }
}

Describe 'Get-ReleasePlan' {
    It 'releases nothing but first releases when nothing changed since the tags' {
        $script:Repo = New-Repo $script:AllFiles $script:AllTags
        Add-Commit $script:Repo @()
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('ipi')
        $plan[0].Version | Should -Be '4.5.0'
        $plan[0].Reason | Should -Be 'first release'
    }

    It 'releases a changed package at the next patch, and its dependents' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('pipeline/engines/a.py')
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('engines', 'dd', 'ipi')
        ($plan | Where-Object Name -eq 'engines').Version | Should -Be '4.5.39'
        ($plan | Where-Object Name -eq 'dd').Version | Should -Be '4.5.97'
        ($plan | Where-Object Name -eq 'dd').Reason |
            Should -Be 'a package it depends on is released'
        ($plan | Where-Object Name -eq 'ipi').Version | Should -Be '4.5.1'
    }

    It 'releases a vendoring package when the vendored folder changes' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('pipeline/owid/a.py')
        @(Get-ReleasePlan $script:Repo $script:Graph).Name | Should -Be @('did')
    }

    It 'releases nothing for a change to an unpublished package' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/examples/a.py')
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'releases nothing for a change outside every package' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('ci/build.ps1', 'device/docs/a.md')
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'releases nothing a second time from a commit already released' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/dd/a.py')
        git -C $script:Repo tag 'dd/4.5.97'
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'continues from the highest tag, not the latest one made' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + @(
            'ipi/4.5.0', 'dd/4.5.9'))
        Add-Commit $script:Repo @('device/dd/a.py')
        (@(Get-ReleasePlan $script:Repo $script:Graph) |
            Where-Object Name -eq 'dd').Version | Should -Be '4.5.97'
    }

    It 'does not read another package''s tags as its own' {
        # 'ipi' must not see tags of a package whose name starts with 'ipi'.
        $graph = $script:Graph + (New-Package 'ipi_cloud' 'ipi/cloud' -FirstVersion '4.5.0')
        $script:Repo = New-Repo ($script:AllFiles + 'ipi/cloud/a.py') (
            $script:AllTags + 'ipi_cloud/4.5.7')
        $plan = @(Get-ReleasePlan $script:Repo $graph)
        ($plan | Where-Object Name -eq 'ipi').Version | Should -Be '4.5.0'
    }

    It 'plans a changed package for a caller that stops on native errors' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/dd/a.py')
        $plan = & {
            $ErrorActionPreference = 'Stop'
            $PSNativeCommandUseErrorActionPreference = $true
            @(Get-ReleasePlan $script:Repo $script:Graph)
        }
        $plan.Name | Should -Be @('dd')
    }

    It 'reads the tags whatever folder it runs from' {
        # A tag pattern would be expanded into the files of a folder that
        # holds one with the package's name, as a repository root holds
        # 'location'.
        $script:Repo = New-Repo $script:AllFiles $script:AllTags
        $here = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Force (Join-Path $here 'location')
        $null = New-Item -ItemType File (Join-Path $here 'location' 'setup.py')
        Push-Location $here
        try {
            (Get-ReleasedVersions $script:Repo 'location')[-1] | Should -Be ([version]'4.5.4')
        } finally {
            Pop-Location
            Remove-Item -Recurse -Force $here
        }
    }

    It 'reads a Go module''s tags, ''<package>/v<version>''' {
        $tags = @($script:AllTags + 'ipi/4.5.0' |
            ForEach-Object { $_.Replace('/', '/v') })
        $script:Repo = New-Repo $script:AllFiles $tags
        Add-Commit $script:Repo @('device/dd/a.py')
        Set-Filter $script:Repo '$true'
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('dd')
        $plan[0].Version | Should -Be '4.5.97'
        Get-FilterCalls $script:Repo |
            Should -Be @('dd dd/v4.5.96 device/dd/a.py')
    }

    It 'counts the changes since the tag, where the tag is off the branch' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        git -C $script:Repo checkout --quiet --detach
        Add-Commit $script:Repo @('device/dd/go.mod')
        git -C $script:Repo tag 'dd/v4.5.97'
        git -C $script:Repo checkout --quiet -
        Add-Commit $script:Repo @()
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('dd')
        $plan[0].Version | Should -Be '4.5.98'
        $plan[0].Reason | Should -Be 'changed since 4.5.97 (1 file)'
    }

    It 'takes the tag with no ''v'' of two of one version' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        git -C $script:Repo tag 'dd/v4.5.97'
        Add-Commit $script:Repo @('device/dd/a.py')
        git -C $script:Repo tag 'dd/4.5.97'
        Add-Commit $script:Repo @()
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'releases nothing a second time from a commit with a Go tag' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/dd/a.py')
        git -C $script:Repo tag 'dd/v4.5.97'
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'does not take a pre-release tag as a release' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/dd/a.py')
        git -C $script:Repo tag 'dd/4.5.97-alpha.1'
        Add-Commit $script:Repo @()
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('dd')
        $plan[0].Version | Should -Be '4.5.97'
    }

    It 'refuses a never-released package with no FirstVersion' {
        $graph = @(New-Package 'new' 'p/new')
        $script:Repo = New-Repo @('p/new/a.py') @()
        { Get-ReleasePlan $script:Repo $graph } | Should -Throw '*FirstVersion*'
    }

    It 'stops rather than read a diff git could not make as no change' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('device/dd/a.py')
        # The highest dd tag is on a file's contents, not on a commit.
        $blob = 'x' | git -C $script:Repo hash-object -w --stdin
        git -C $script:Repo tag 'dd/4.5.200' $blob
        { Get-ReleasePlan $script:Repo $script:Graph } |
            Should -Throw '*changes to dd since dd/4.5.200*'
    }
}

Describe 'Get-PackageVersions' {
    It 'gives each published package its planned version or its last release' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        Add-Commit $script:Repo @('pipeline/engines/a.py')
        $versions = Get-PackageVersions $script:Repo $script:Graph
        @($versions.Keys) | Should -Be @(
            'core', 'engines', 'did', 'dd', 'location', 'ipi')
        @($versions.Values.Version) | Should -Be @(
            '4.5.38', '4.5.39', '4.5.38', '4.5.97', '4.5.4', '4.5.1')
        @($versions.Values.Release) | Should -Be @(
            $false, $true, $false, $true, $false, $true)
        $versions['engines'].Previous | Should -Be ([version]'4.5.38')
        $versions['engines'].Reason | Should -Be 'changed since 4.5.38 (1 file)'
        $versions['core'].Previous | Should -Be ([version]'4.5.38')
        $versions['core'].Reason | Should -Be 'unchanged since 4.5.38'
        $versions['dd'].Path | Should -Be 'device/dd'
    }

    It 'gives a first release its FirstVersion and no previous release' {
        $script:Repo = New-Repo $script:AllFiles $script:AllTags
        Add-Commit $script:Repo @()
        $ipi = (Get-PackageVersions $script:Repo $script:Graph)['ipi']
        $ipi.Version | Should -Be '4.5.0'
        $ipi.Previous | Should -BeNullOrEmpty
        $ipi.Release | Should -BeTrue
    }

    It 'takes a plan the caller already has' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        $plan = @([pscustomobject]@{
            Name = 'dd'; Path = 'device/dd'; Version = '4.5.97'
            Previous = [version]'4.5.96'; Reason = 'given' })
        $versions = Get-PackageVersions $script:Repo $script:Graph $plan
        $versions['dd'].Version | Should -Be '4.5.97'
        $versions['dd'].Reason | Should -Be 'given'
        $versions['engines'].Release | Should -BeFalse
    }

    It 'stops on a package never released that the plan leaves out' {
        $script:Repo = New-Repo $script:AllFiles $script:AllTags
        { Get-PackageVersions $script:Repo $script:Graph @() } |
            Should -Throw '*ipi has never been released*'
    }

    It 'reads ci/packages.json when given no package list' {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
        $null = New-Item -ItemType Directory -Force (Join-Path $script:Repo 'ci')
        $script:Graph | ConvertTo-Json |
            Set-Content (Join-Path $script:Repo 'ci' 'packages.json')
        Add-Commit $script:Repo @('location/setup.py')
        $versions = Get-PackageVersions $script:Repo
        $versions['location'].Version | Should -Be '4.5.5'
        @($versions.Keys).Count | Should -Be 6
    }
}

Describe 'Get-ReleasePlan, for files that do not count' {
    BeforeEach {
        $script:Repo = New-Repo $script:AllFiles ($script:AllTags + 'ipi/4.5.0')
    }

    It 'releases nothing for a change only to a README, dependents included' {
        Add-Commit $script:Repo @('pipeline/engines/README.md')
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'releases a README change of a package that sets IgnoreDefaults false' {
        $graph = Set-Package $script:Graph (New-Package 'engines' `
            'pipeline/engines' @('core') -IgnoreDefaults $false)
        Add-Commit $script:Repo @('pipeline/engines/README.md')
        $plan = @(Get-ReleasePlan $script:Repo $graph)
        $plan.Name | Should -Be @('engines', 'dd', 'ipi')
        $plan[0].Reason | Should -Be 'changed since 4.5.38 (1 file)'
    }

    It 'releases nothing for a change only to tests, examples or docs' {
        Add-Commit $script:Repo @(
            'device/dd/tests/test_a.py', 'device/dd/src/test/b.py',
            'device/dd/examples/c.py', 'device/dd/docs/d.html',
            'device/dd/LICENSE', 'location/LICENSE.txt', 'location/docs/e.md',
            'pipeline/owid/tests/f.py')
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'releases nothing for tests, examples or docs whatever their case' {
        Add-Commit $script:Repo @(
            'device/dd/Tests/a.cs', 'device/dd/Test/b.cs',
            'device/dd/Examples/c.cs', 'device/dd/Docs/d.html',
            'device/dd/Readme.MD', 'location/License.txt')
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
    }

    It 'matches a package''s own Ignore in its case' {
        $graph = Set-Package $script:Graph (New-Package 'dd' 'device/dd' `
            @('engines') -Ignore @('device/dd/*.cfg'))
        Add-Commit $script:Repo @('device/dd/setup.CFG')
        @(Get-ReleasePlan $script:Repo $graph).Name | Should -Be @('dd')
    }

    It 'leaves out a file the package''s own Ignore matches' {
        Add-Commit $script:Repo @('device/dd/setup.cfg')
        @(Get-ReleasePlan $script:Repo $script:Graph).Name | Should -Be @('dd')
        $graph = Set-Package $script:Graph (New-Package 'dd' 'device/dd' `
            @('engines') -Ignore @('device/dd/*.cfg'))
        @(Get-ReleasePlan $script:Repo $graph).Count | Should -Be 0
    }

    It 'counts only the file that counts in a change that also edits a README' {
        Add-Commit $script:Repo @('device/dd/a.py', 'device/dd/README.md')
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('dd')
        $plan[0].Version | Should -Be '4.5.97'
        $plan[0].Reason | Should -Be 'changed since 4.5.96 (1 file)'
    }

    It 'still releases a dependent with what it depends on' {
        Add-Commit $script:Repo @('pipeline/engines/a.py',
            'device/dd/README.md')
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('engines', 'dd', 'ipi')
        ($plan | Where-Object Name -eq 'dd').Reason |
            Should -Be 'a package it depends on is released'
    }

    It 'counts every file outside the defaults, with no filter and no Ignore' {
        Add-Commit $script:Repo @('device/dd/a.py', 'device/dd/src/b.json',
            'pipeline/owid/c.py', 'location/setup.py')
        $plan = @(Get-ReleasePlan $script:Repo $script:Graph)
        $plan.Name | Should -Be @('dd', 'did', 'location')
        $plan.Version | Should -Be @('4.5.97', '4.5.39', '4.5.5')
        $plan.Reason | Should -Be @('changed since 4.5.96 (2 files)',
            'changed since 4.5.38 (1 file)', 'changed since 4.5.4 (1 file)')
    }

    It 'reads Ignore and IgnoreDefaults from ci/packages.json' {
        $graph = Set-Package $script:Graph (New-Package 'dd' 'device/dd' `
            @('engines') -Ignore @('device/dd/*.cfg'))
        $graph = Set-Package $graph (New-Package 'engines' 'pipeline/engines' `
            @('core') -IgnoreDefaults $false)
        $null = New-Item -ItemType Directory -Force (Join-Path $script:Repo 'ci')
        $graph | ConvertTo-Json |
            Set-Content (Join-Path $script:Repo 'ci' 'packages.json')
        Add-Commit $script:Repo @('device/dd/setup.cfg',
            'pipeline/engines/README.md')
        $plan = @(Get-ReleasePlan $script:Repo)
        $plan.Name | Should -Be @('engines', 'dd', 'ipi')
        ($plan | Where-Object Name -eq 'dd').Reason |
            Should -Be 'a package it depends on is released'
    }

    It 'ignores the defaults whatever folder it runs from' {
        # PowerShell on Linux and macOS would replace an argument such as
        # '**/*.md' with the files it matches in the current folder.
        $here = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        foreach ($file in @('README.md', 'docs/a.md', 'device/dd/README.md')) {
            $full = Join-Path $here $file
            $null = New-Item -ItemType Directory -Force (Split-Path $full)
            $null = New-Item -ItemType File $full
        }
        Add-Commit $script:Repo @('device/dd/README.md')
        Push-Location $here
        try {
            @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
        } finally {
            Pop-Location
            Remove-Item -Recurse -Force $here
        }
    }

    It 'releases nothing when the filter script drops every file left' {
        Add-Commit $script:Repo @('device/dd/package.json')
        Set-Filter $script:Repo '$_ -notlike ''*/package.json'''
        @(Get-ReleasePlan $script:Repo $script:Graph).Count | Should -Be 0
        Get-FilterCalls $script:Repo |
            Should -Be @('dd dd/4.5.96 device/dd/package.json')
    }

    It 'releases what the filter keeps, called only with files left' {
        Add-Commit $script:Repo @('device/dd/package.json',
            'pipeline/core/README.md')
        Set-Filter $script:Repo '$true'
        # common-ci runs a repository's scripts from the folder that holds
        # the repository, and names it by its folder.
        $name = Split-Path -Leaf $script:Repo
        Push-Location (Split-Path $script:Repo)
        try {
            $plan = @(Get-ReleasePlan $name $script:Graph)
        } finally {
            Pop-Location
        }
        $plan.Name | Should -Be @('dd')
        $plan[0].Reason | Should -Be 'changed since 4.5.96 (1 file)'
        Get-FilterCalls $script:Repo |
            Should -Be @('dd dd/4.5.96 device/dd/package.json')
    }

    It 'leaves no exit code from the filter script for its caller to see' {
        # ipi is the last package the plan reads, so no later git command
        # clears the 1 the filter leaves.
        Add-Commit $script:Repo @('ipi/ipi/a.py')
        Set-Filter $script:Repo '$true'
        Add-Content (Join-Path $script:Repo 'ci' 'release-plan-filter.ps1') `
            'git -C $RepoPath diff --quiet HEAD~1 HEAD'
        $global:LASTEXITCODE = 0
        @(Get-ReleasePlan $script:Repo $script:Graph).Name | Should -Be @('ipi')
        $LASTEXITCODE | Should -Be 0
    }

    It 'stops on a path the filter returns that it was not given' {
        Add-Commit $script:Repo @('device/dd/a.py')
        $null = New-Item -ItemType Directory -Force (Join-Path $script:Repo 'ci')
        Set-Content (Join-Path $script:Repo 'ci' 'release-plan-filter.ps1') @(
            'param($RepoPath, $Package, $From, [string[]]$Files)'
            '$Files | ForEach-Object { $_.ToUpperInvariant() }')
        { Get-ReleasePlan $script:Repo $script:Graph } |
            Should -Throw '*DEVICE/DD/A.PY*dd*not one of the files*'
    }

    It 'refuses IgnoreDefaults given as text' {
        $graph = Set-Package $script:Graph (New-Package 'dd' 'device/dd' @('engines'))
        $graph | Where-Object Name -eq 'dd' |
            Add-Member -NotePropertyName IgnoreDefaults -NotePropertyValue 'false' -Force
        Add-Commit $script:Repo @('device/dd/a.py')
        { Get-ReleasePlan $script:Repo $graph } |
            Should -Throw "*dd gives IgnoreDefaults as 'false'*true or false*"
    }
}

}
