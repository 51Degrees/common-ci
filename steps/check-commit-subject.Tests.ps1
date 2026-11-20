# Tests for steps/check-commit-subject.ps1.
#
# The exit code is the decision. The output is checked where it tells a person
# which subject was refused and which prefixes are allowed. Tests of a range
# build a throwaway git repository with the commits a test needs.

BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'check-commit-subject.ps1'

    # Runs the check and returns its exit code and output together.
    function Invoke-Check ([hashtable]$Arguments) {
        $output = & $script:Check @Arguments | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    # A repository with a first commit tagged 'start', then one commit for
    # each subject given.
    function New-Repo ([string[]]$Subjects) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        git -C $path -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'DOC: Start.'
        git -C $path tag start
        foreach ($subject in $Subjects) {
            git -C $path -c user.name=test -c user.email=test@example.com `
                commit --quiet --allow-empty -m $subject
        }
        return $path
    }
}

Describe 'check-commit-subject.ps1' {

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
}

Describe 'with subjects given' {
    It 'passes a subject starting with <_> and a colon' -ForEach @(
            'FEAT', 'BUG', 'OPTIM', 'TEST', 'REORG', 'DOC', 'REF', 'BUILD') {
        $result = Invoke-Check @{ Subject = "${_}: Change something." }
        $result.ExitCode | Should -Be 0
    }

    It 'refuses a subject with no prefix, naming it and the allowed prefixes' {
        $result = Invoke-Check @{ Subject = 'Fixed the build.' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "'Fixed the build\.'"
        $result.Output | Should -Match 'FEAT:, BUG:, OPTIM:, TEST:, REORG:, DOC:, REF:, BUILD:'
    }

    It 'refuses a prefix with no colon' {
        (Invoke-Check @{ Subject = 'BUG Fixed the build.' }).ExitCode | Should -Be 1
    }

    It 'refuses a prefix in lower case' {
        (Invoke-Check @{ Subject = 'bug: Fixed the build.' }).ExitCode | Should -Be 1
    }

    It 'refuses a longer word that starts with a prefix' {
        (Invoke-Check @{ Subject = 'FEATURE: Add a thing.' }).ExitCode | Should -Be 1
    }

    It 'refuses a prefix that is not at the start' {
        (Invoke-Check @{ Subject = ' BUG: Fixed the build.' }).ExitCode | Should -Be 1
    }

    It 'refuses a prefix that is not one of the allowed' {
        (Invoke-Check @{ Subject = 'CHORE: Tidy.' }).ExitCode | Should -Be 1
    }

    It 'refuses an empty subject' {
        (Invoke-Check @{ Subject = '' }).ExitCode | Should -Be 1
    }

    It 'checks every subject, naming each one refused' {
        $result = Invoke-Check @{ Subject = @('DOC: Good.', 'Bad one.', 'Bad two.') }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "'Bad one\.'"
        $result.Output | Should -Match "'Bad two\.'"
        $result.Output | Should -Not -Match "'DOC: Good\.' does not"
    }
}

Describe 'with a range of commits' {
    It 'passes when every commit in the range has a prefix' {
        $script:Repo = New-Repo @('FEAT: Add a thing.', 'TEST: Test the thing.')
        $result = Invoke-Check @{ RepoName = $script:Repo; Range = 'start..HEAD' }
        $result.ExitCode | Should -Be 0
    }

    It 'refuses a commit in the range with no prefix, naming its subject' {
        $script:Repo = New-Repo @('FEAT: Add a thing.', 'Tidy up.')
        $result = Invoke-Check @{ RepoName = $script:Repo; Range = 'start..HEAD' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "'Tidy up\.'"
    }

    It 'leaves out commits before the range' {
        $script:Repo = New-Repo @()
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'Old commit with no prefix.'
        git -C $script:Repo tag old
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'BUG: New commit.'
        (Invoke-Check @{ RepoName = $script:Repo; Range = 'old..HEAD' }
        ).ExitCode | Should -Be 0
    }

    It 'leaves out merge commits, whose subjects git or GitHub write' {
        $script:Repo = New-Repo @()
        git -C $script:Repo checkout --quiet -b feature
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'BUG: On a branch.'
        git -C $script:Repo checkout --quiet -
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet --allow-empty -m 'DOC: On the first branch.'
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            merge --quiet --no-ff -m 'Merge branch feature' feature
        (Invoke-Check @{ RepoName = $script:Repo; Range = 'start..HEAD' }
        ).ExitCode | Should -Be 0
    }

    It 'passes an empty range' {
        $script:Repo = New-Repo @()
        $result = Invoke-Check @{ RepoName = $script:Repo; Range = 'start..HEAD' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'No commit to check'
    }
}

It 'stops when given neither subjects nor a range, rather than passing' {
    { & $script:Check } | Should -Throw '*Give -Subject*'
}

}
