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

Describe 'several packages, with -Plan' {
    BeforeEach {
        $script:Repo = New-TaggedRepo @(
            'core/4.5.38', 'dd/4.5.96', 'pipeline/v4.5.171')
        # Stands in for a repository's registry: gives the versions in
        # $global:Registry and records each call in $global:RegistryCalls.
        $script:Registry = Join-Path $TestDrive 'registry-version.ps1'
        Set-Content $script:Registry @(
            'param([string]$RepoName, $Package)'
            '$global:RegistryCalls += , "$RepoName $($Package.Name)"'
            '$global:Registry[$Package.Name]')
        $global:Registry = @{}
        $global:RegistryCalls = @()
    }

    It 'passes when every package moves only its patch, and names each' {
        $result = Invoke-Check @{ RepoName = $script:Repo; Plan = @(
            [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }
            [pscustomobject]@{ Name = 'pipeline'; Version = '4.5.172' }) }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'core 4\.5\.39, against its own tags'
        $result.Output | Should -Match 'against 4\.5\.38 already released'
        $result.Output | Should -Match 'pipeline 4\.5\.172, against its own tags'
        $result.Output | Should -Match 'against 4\.5\.171 already released'
    }

    It 'refuses when any package moves its minor place, naming those refused' {
        $result = Invoke-Check @{ RepoName = $script:Repo; Plan = @(
            [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }
            [pscustomobject]@{ Name = 'dd'; Version = '4.6.0' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'these packages were refused: dd\.'
    }

    It 'allows the move when ALLOW_VERSION_BUMP is set' {
        $env:ALLOW_VERSION_BUMP = 'true'
        (Invoke-Check @{ RepoName = $script:Repo; Plan = @(
            [pscustomobject]@{ Name = 'dd'; Version = '4.6.0' }) }
        ).ExitCode | Should -Be 0
    }

    It 'passes a plan with nothing in it' {
        $result = Invoke-Check @{ RepoName = $script:Repo; Plan = @() }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'nothing to check'
    }

    It 'takes the release plan''s own entries' {
        $plan = @([pscustomobject]@{
            Name = 'dd'; Path = 'device/dd'; Version = '4.5.97'
            Previous = [version]'4.5.96'; Reason = 'changed since 4.5.96 (1 file)' })
        (Invoke-Check @{ RepoName = $script:Repo; Plan = $plan }).ExitCode |
            Should -Be 0
    }

    It 'also refuses a move against the version the registry gives' {
        $global:Registry = @{ dd = '4.4.10' }
        $result = Invoke-Check @{
            RepoName = $script:Repo; RegistryVersionScript = $script:Registry
            Plan = @(
                [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }
                [pscustomobject]@{ Name = 'dd'; Version = '4.5.97' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'dd 4\.5\.97, against 4\.4\.10 in its registry'
        $result.Output | Should -Match 'these packages were refused: dd\.'
        $global:RegistryCalls | Should -Be @(
            "$($script:Repo) core", "$($script:Repo) dd")
    }

    It 'checks a package the registry does not have against its tags alone' {
        $global:Registry = @{ dd = '4.5.96' }
        $result = Invoke-Check @{
            RepoName = $script:Repo; RegistryVersionScript = $script:Registry
            Plan = @(
                [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }
                [pscustomobject]@{ Name = 'dd'; Version = '4.5.97' }) }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'core 4\.5\.39, against .* in its registry'
        $result.Output | Should -Match 'dd 4\.5\.97, against 4\.5\.96 in its registry'
    }

    It 'refuses a package with no tag that the registry gives as $null' {
        # As a .NET family with no tag and no listed NuGet version.
        $result = Invoke-Check @{
            RepoName = $script:Repo; RegistryVersionScript = $script:Registry
            Plan = @(
                [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }
                [pscustomobject]@{ Name = 'ipi'; Version = '4.5.0' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'First release refused::ipi has no tag here'
        $result.Output | Should -Match 'these packages were refused: ipi\.'
    }

    It 'refuses a package with no tag that the registry gives nothing for' {
        # As a Node package with no tag that npm does not have.
        $none = Join-Path $TestDrive 'registry-none.ps1'
        Set-Content $none 'param([string]$RepoName, $Package)'
        $result = Invoke-Check @{
            RepoName = $script:Repo; RegistryVersionScript = $none
            Plan = @([pscustomobject]@{ Name = 'ipi'; Version = '4.5.0' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'First release refused::ipi has no tag here'
    }

    It 'checks a package with no tag against the version the registry gives' {
        $global:Registry = @{ ipi = '4.5.0' }
        $result = Invoke-Check @{
            RepoName = $script:Repo; RegistryVersionScript = $script:Registry
            Plan = @([pscustomobject]@{ Name = 'ipi'; Version = '4.5.1' }) }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'ipi 4\.5\.1, against 4\.5\.0 in its registry'
        $result.Output | Should -Not -Match 'First release refused'
    }

    It 'stops when given a registry script without a plan' {
        { & $script:Check -RepoName $script:Repo -Version '4.5.39' `
            -TagPrefix 'core' -RegistryVersionScript $script:Registry } |
            Should -Throw '*Give -RegistryVersionScript only with -Plan*'
    }

    It 'stops on an entry with no Version' {
        { & $script:Check -RepoName $script:Repo -Plan @(
            [pscustomobject]@{ Name = 'core' }) } |
            Should -Throw '*needs a Name and a Version*'
    }

    It 'stops when given a plan and a single version' {
        { & $script:Check -RepoName $script:Repo -Version '4.5.39' -Plan @(
            [pscustomobject]@{ Name = 'core'; Version = '4.5.39' }) } |
            Should -Throw '*Give -Plan with -RepoName*'
    }

    It 'stops when given neither a version nor a plan' {
        { & $script:Check -RepoName $script:Repo } |
            Should -Throw '*Give -Version*'
    }
}

}
