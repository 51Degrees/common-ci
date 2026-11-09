# Tests for steps/version-tags.ps1.
#
# Each tag form below is one that a repository calling common-ci has today.
# The tests of Get-VersionTags build a throwaway git repository.

BeforeAll {
    . (Join-Path $PSScriptRoot 'version-tags.ps1')

    # A repository with one commit per entry, each entry the tags to put on
    # that commit.
    function New-TaggedRepo([string[][]]$Commits) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        foreach ($tags in $Commits) {
            git -C $path -c user.name=test -c user.email=test@example.com `
                commit --quiet --allow-empty -m 'Change'
            foreach ($tag in $tags) {
                git -C $path tag $tag
            }
        }
        return $path
    }
}

Describe 'version-tags.ps1' {

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
}

Describe 'ConvertFrom-VersionTag' {
    It 'reads <Tag> as <Version>' -TestCases @(
        @{ Tag = '4.5.103'; Version = '4.5.103' }
        @{ Tag = 'v4.5.29'; Version = '4.5.29' }
        @{ Tag = '4.4.3.0'; Version = '4.4.3' }
        @{ Tag = '4.3.5+2'; Version = '4.3.5' }
    ) {
        ConvertFrom-VersionTag $Tag | Should -Be ([version]$Version)
    }

    It 'reads <Tag> as <Version> for the package <Prefix>' -TestCases @(
        @{ Tag = 'pipeline/4.5.129'; Prefix = 'pipeline'; Version = '4.5.129' }
        @{ Tag = 'pipeline/v4.5.171'; Prefix = 'pipeline'; Version = '4.5.171' }
        @{ Tag = 'fiftyone_pipeline_core/4.5.42'
            Prefix = 'fiftyone_pipeline_core'; Version = '4.5.42' }
    ) {
        ConvertFrom-VersionTag $Tag -Prefix $Prefix |
            Should -Be ([version]$Version)
    }

    It 'does not take the pre-release <Tag> as a release' -TestCases @(
        @{ Tag = '4.5.8-49' }
        @{ Tag = 'v4.5.0-alpha.1' }
        @{ Tag = '4.1.0-beta.13+1' }
        @{ Tag = 'v4.1.0-beta0003' }
        @{ Tag = '4.5.19-fix-62-permalink-agnostic-endpoint.1' }
    ) {
        ConvertFrom-VersionTag $Tag -AnyPrefix | Should -BeNullOrEmpty
    }

    It 'does not take <Tag> as a release' -TestCases @(
        @{ Tag = 'v1' }
        @{ Tag = 'zig' }
        @{ Tag = 'v0.1' }
        @{ Tag = 'examples-assets-v1.0.0' }
        @{ Tag = 'V4.5.1' }
        @{ Tag = '4.5.1.0.0' }
    ) {
        ConvertFrom-VersionTag $Tag -AnyPrefix | Should -BeNullOrEmpty
    }

    It 'reads a package''s tag only when asked for packages' {
        ConvertFrom-VersionTag 'pipeline/4.5.1' | Should -BeNullOrEmpty
        ConvertFrom-VersionTag 'pipeline/4.5.1' -AnyPrefix |
            Should -Be ([version]'4.5.1')
        ConvertFrom-VersionTag 'release/4.5.1' -AnyPrefix |
            Should -Be ([version]'4.5.1')
    }

    It 'reads only the package''s own tags with -Prefix' {
        ConvertFrom-VersionTag '4.5.1' -Prefix 'pipeline' | Should -BeNullOrEmpty
        ConvertFrom-VersionTag 'pipeline_extra/4.5.1' -Prefix 'pipeline' |
            Should -BeNullOrEmpty
        ConvertFrom-VersionTag 'pipeline/web/4.5.1' -Prefix 'pipeline' |
            Should -BeNullOrEmpty
        ConvertFrom-VersionTag 'Pipeline/4.5.1' -Prefix 'pipeline' |
            Should -BeNullOrEmpty
    }
}

Describe 'Get-VersionTags' {
    It 'lists the release tags, highest version last' {
        $script:Repo = New-TaggedRepo @(
            , @('4.5.10', '4.5.9', 'v4.5.11-alpha.1', 'zig', 'dd/4.5.96'))
        $tags = @(Get-VersionTags $script:Repo)
        $tags.Tag | Should -Be @('4.5.9', '4.5.10')
        $tags[-1].Version | Should -Be ([version]'4.5.10')
    }

    It 'lists every package''s tags with -AnyPrefix' {
        $script:Repo = New-TaggedRepo @(, @('4.5.10', 'dd/4.5.96', 'go/v4.5.1'))
        (Get-VersionTags $script:Repo -AnyPrefix).Tag |
            Should -Be @('go/v4.5.1', '4.5.10', 'dd/4.5.96')
    }

    It 'lists one package''s tags with -Prefix, in either form' {
        $script:Repo = New-TaggedRepo @(
            , @('pipeline/v4.5.170', 'pipeline/4.5.169', 'pipeline_x/4.6.0'))
        (Get-VersionTags $script:Repo -Prefix 'pipeline').Tag |
            Should -Be @('pipeline/4.5.169', 'pipeline/v4.5.170')
    }

    It 'puts the tag with no ''v'' last of two of one version' {
        $script:Repo = New-TaggedRepo @(, @('pipeline/v4.5.171', 'pipeline/4.5.171'))
        (Get-VersionTags $script:Repo -Prefix 'pipeline')[-1].Tag |
            Should -Be 'pipeline/4.5.171'
    }

    It 'lists only the tags on HEAD with -AtHead' {
        $script:Repo = New-TaggedRepo @(@('dd/4.5.96'), @('dd/v4.5.97'))
        (Get-VersionTags $script:Repo -Prefix 'dd' -AtHead).Tag |
            Should -Be @('dd/v4.5.97')
    }

    It 'lists only the tags on HEAD or before it with -Merged' {
        $script:Repo = New-TaggedRepo @(@('dd/4.5.96'), @('dd/4.5.97'))
        git -C $script:Repo checkout --quiet HEAD~1
        (Get-VersionTags $script:Repo -Prefix 'dd' -Merged).Tag |
            Should -Be @('dd/4.5.96')
    }

    It 'is empty for a repository with no release tags' {
        $script:Repo = New-TaggedRepo @(, @('zig'))
        @(Get-VersionTags $script:Repo -AnyPrefix).Count | Should -Be 0
    }
}

}
