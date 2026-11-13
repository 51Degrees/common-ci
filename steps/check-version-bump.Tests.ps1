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

Describe 'a branch with no tags' {
    It 'refuses 0.0.1, the version GitVersion gives a branch with no tags' {
        # The fault behind common-ci#251: fiftyone_ipintelligence_cloud 0.0.1.
        $script:Repo = New-TaggedRepo @()
        $result = Invoke-Check @{ Version = '0.0.1'; RepoName = $script:Repo }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'First release refused'
    }

    It 'refuses any version, because nobody has decided where it starts' {
        $script:Repo = New-TaggedRepo @()
        (Invoke-Check @{ Version = '4.5.0'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }

    It 'is not talked out of the refusal by ALLOW_VERSION_BUMP' {
        # That switch is for a deliberate major or minor move, not for a number
        # nobody chose.
        $script:Repo = New-TaggedRepo @()
        $env:ALLOW_VERSION_BUMP = 'true'
        (Invoke-Check @{ Version = '0.0.1'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }

    It 'refuses a branch whose only tags are not releases' {
        $script:Repo = New-TaggedRepo @('4.5.0-alpha.1', 'zig')
        $result = Invoke-Check @{ Version = '4.5.0'; RepoName = $script:Repo }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'First release refused'
    }

    It 'refuses a new package when no package has a release tag' {
        $script:Repo = New-TaggedRepo @('fiftyone_pipeline_core/4.5.38-alpha.1')
        (Invoke-Check @{
            Version = '4.5.0'; RepoName = $script:Repo; TagPrefix = 'fiftyone_ipintelligence' }
        ).ExitCode | Should -Be 1
    }

    It 'refuses a new package when the only release tag is off the branch' {
        $script:Repo = New-TaggedRepo @()
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'Elsewhere'
        git -C $script:Repo tag 'fiftyone_pipeline_core/4.5.38'
        git -C $script:Repo reset --quiet --hard HEAD~1
        (Invoke-Check @{
            Version = '4.5.0'; RepoName = $script:Repo; TagPrefix = 'fiftyone_ipintelligence' }
        ).ExitCode | Should -Be 1
    }

}

Describe 'a package on a 0.x line' {
    It 'is checked like any other once its branch has a tag' {
        $script:Repo = New-TaggedRepo @('0.0.5')
        (Invoke-Check @{ Version = '0.0.6'; RepoName = $script:Repo }).ExitCode | Should -Be 0
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

Describe 'the tag forms version-tags.ps1 reads' {
    It 'reads a ''v'' before the version' {
        $script:Repo = New-TaggedRepo @('v4.5.29')
        (Invoke-Check @{ Version = '4.5.30'; RepoName = $script:Repo }).ExitCode | Should -Be 0
        (Invoke-Check @{ Version = '4.6.0'; RepoName = $script:Repo }).ExitCode | Should -Be 1
    }

    It 'reads a Go module''s tags with -TagPrefix' {
        $script:Repo = New-TaggedRepo @('pipeline/v4.5.171', 'common/v4.6.0')
        $result = Invoke-Check @{
            Version = '4.5.172'; RepoName = $script:Repo; TagPrefix = 'pipeline' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'against 4\.5\.171 already released'
    }

    It 'reads build metadata and a fourth number as the version before them' {
        $script:Repo = New-TaggedRepo @('4.4.49+2', '4.4.3.0')
        $result = Invoke-Check @{ Version = '4.4.50'; RepoName = $script:Repo }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'against 4\.4\.49 already released'
    }

    It 'does not take a pre-release of a minor version as releasing it' {
        $script:Repo = New-TaggedRepo @('4.5.96', '4.6.0-alpha.1')
        $result = Invoke-Check @{ Version = '4.6.0'; RepoName = $script:Repo }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'against 4\.5\.96 already released'
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

    It 'lets a new package make its first release beside tagged ones' {
        # The branch has tags, so the repository's release history is there;
        # the new package's first number was chosen by the repository.
        $script:Repo = New-TaggedRepo @('fiftyone_pipeline_core/4.5.38')
        (Invoke-Check @{
            Version = '4.5.0'; RepoName = $script:Repo; TagPrefix = 'fiftyone_ipintelligence' }
        ).ExitCode | Should -Be 0
    }
}

}
