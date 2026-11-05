# Tests for steps/release-plan.ps1.
#
# The selection rules are tested against a small package list written here, so
# a test states exactly which graph it relies on. The release plan reads tags
# and diffs, so those tests build a throwaway git repository.

BeforeAll {
    . (Join-Path $PSScriptRoot 'release-plan.ps1')

    function New-Package([string]$Name, [string]$Path,
            [string[]]$DependsOn = @(), [bool]$Publish = $true,
            [string]$FirstVersion = $null, [string[]]$ExtraPaths = $null) {
        $package = [pscustomobject]@{
            Name = $Name; Path = $Path
            DependsOn = $DependsOn; Publish = $Publish
            FirstVersion = $FirstVersion
        }
        if ($ExtraPaths) {
            $package | Add-Member ExtraPaths $ExtraPaths
        }
        return $package
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
        # 'git diff --quiet' exits 1 for a changed package.
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

    It 'refuses a never-released package with no FirstVersion' {
        $graph = @(New-Package 'new' 'p/new')
        $script:Repo = New-Repo @('p/new/a.py') @()
        { Get-ReleasePlan $script:Repo $graph } | Should -Throw '*FirstVersion*'
    }
}

}
