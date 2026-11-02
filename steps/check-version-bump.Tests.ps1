# Tests for steps/check-version-bump.ps1.
#
# The script reads release history from a checkout's tags, so each test builds
# a throwaway git repository with the tags it needs and runs the script against
# it. The exit code is the decision; the output is only checked where the
# wording is what tells a person what to do next.

BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'check-version-bump.ps1'

    # A repository with one commit and the given tags. Returned as a path the
    # script can be pointed at with -RepoName.
    function New-TaggedRepo ([string[]]$Tags) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        git -C $path -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'Start'
        foreach ($tag in $Tags) {
            git -C $path tag $tag
        }
        return $path
    }

    # Runs the check and returns its exit code and output together.
    function Invoke-Check ([hashtable]$Arguments) {
        $output = & $script:Check @Arguments | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe 'check-version-bump.ps1' {

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
    $env:ALLOW_VERSION_BUMP = $null
}

Describe 'a repository that has never released' {
    It 'refuses 0.0.1, the version GitVersion gives a repository with no tags' {
        # The fault behind common-ci#251: fiftyone_ipintelligence_cloud 0.0.1.
        $script:Repo = New-TaggedRepo @()
        $result = Invoke-Check @{ Version = '0.0.1'; RepoName = $script:Repo }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'First version refused'
    }

    It 'refuses any other 0.x first release' {
        $script:Repo = New-TaggedRepo @()
        (Invoke-Check @{ Version = '0.3.0'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }

    It 'accepts a chosen 4.5 first release' {
        $script:Repo = New-TaggedRepo @()
        (Invoke-Check @{ Version = '4.5.0'; RepoName = $script:Repo }).ExitCode | Should -Be 0
    }

    It 'is not talked out of the refusal by ALLOW_VERSION_BUMP' {
        # That switch is for a deliberate major or minor move, not for a number
        # nobody chose.
        $script:Repo = New-TaggedRepo @()
        $env:ALLOW_VERSION_BUMP = 'true'
        (Invoke-Check @{ Version = '0.0.1'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }
}

Describe 'a repository with plain version tags' {
    It 'accepts the next patch' {
        $script:Repo = New-TaggedRepo @('4.5.95', '4.5.96')
        (Invoke-Check @{ Version = '4.5.97'; RepoName = $script:Repo }).ExitCode | Should -Be 0
    }

    It 'refuses a minor move' {
        $script:Repo = New-TaggedRepo @('4.5.96')
        (Invoke-Check @{ Version = '4.6.0'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }

    It 'allows a minor move when ALLOW_VERSION_BUMP is set' {
        $script:Repo = New-TaggedRepo @('4.5.96')
        $env:ALLOW_VERSION_BUMP = 'true'
        (Invoke-Check @{ Version = '4.6.0'; RepoName = $script:Repo }).ExitCode | Should -Be 0
    }

    It 'ignores package tags when no prefix is given' {
        # Without -TagPrefix only plain version tags are history, as before
        # this change, so a package tag cannot raise the highest version.
        $script:Repo = New-TaggedRepo @('4.5.96', 'fiftyone_pipeline_core/4.9.0')
        (Invoke-Check @{ Version = '4.5.97'; RepoName = $script:Repo }).ExitCode | Should -Be 0
    }
}

Describe 'one package of a monorepo, with -TagPrefix' {
    It 'compares with that package''s own tags only' {
        # The repository holds a package at 4.5.96; this one is at 4.5.38 and
        # moving to 4.5.39 is a patch for it.
        $script:Repo = New-TaggedRepo @(
            'fiftyone_devicedetection/4.5.96',
            'fiftyone_pipeline_core/4.5.38')
        $result = Invoke-Check @{
            Version = '4.5.39'; RepoName = $script:Repo; TagPrefix = 'fiftyone_pipeline_core' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'against 4\.5\.38 already released'
    }

    It 'refuses a minor move against that package''s own history' {
        $script:Repo = New-TaggedRepo @(
            'fiftyone_pipeline_core/4.5.38', 'fiftyone_devicedetection/4.6.0')
        (Invoke-Check @{
            Version = '4.6.0'; RepoName = $script:Repo; TagPrefix = 'fiftyone_pipeline_core' }
        ).ExitCode | Should -Be 1
    }

    It 'does not take a longer package name as its own' {
        # fiftyone_pipeline_core is a prefix of the name of another package; its
        # history must not include that package's tags.
        $script:Repo = New-TaggedRepo @(
            'fiftyone_pipeline_core_extra/4.6.0', 'fiftyone_pipeline_core/4.5.38')
        (Invoke-Check @{
            Version = '4.5.39'; RepoName = $script:Repo; TagPrefix = 'fiftyone_pipeline_core' }
        ).ExitCode | Should -Be 0
    }

    It 'treats a package with no tags of its own as never released' {
        $script:Repo = New-TaggedRepo @('fiftyone_pipeline_core/4.5.38')
        (Invoke-Check @{
            Version = '4.5.0'; RepoName = $script:Repo; TagPrefix = 'fiftyone_ipintelligence' }
        ).ExitCode | Should -Be 0
        (Invoke-Check @{
            Version = '0.0.1'; RepoName = $script:Repo; TagPrefix = 'fiftyone_ipintelligence' }
        ).ExitCode | Should -Be 1
    }
}

}
