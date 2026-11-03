# Tests for steps/merge-pr.ps1.
#
# `gh` is replaced by a function that describes one pull request and records
# whether the merge was asked for, so no test reaches GitHub.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'merge-pr.ps1'

    # The pull request `gh` answers for. Global, because the step calls `gh`
    # from its own script scope.
    function Set-PullRequest ([string]$Base) {
        $global:MergePrTest = @{ Base = $Base; Merged = $false }
    }

    function gh {
        $test = $global:MergePrTest
        if ($args[0] -eq 'pr' -and $args[1] -eq 'view') {
            return '{"number":7,"headRefName":"update-submodules/' + $test.Base +
                '","baseRefName":"' + $test.Base + '","title":"Update submodules"}'
        }
        if ($args[0] -eq 'api' -and $args[1] -eq '/repos/org/demo/pulls/7/merge') {
            $test.Merged = $true
            return '{"merged":true}'
        }
        throw "Unexpected call: gh $args"
    }

    # The step only sets an exit code when it refuses, so the last test's code
    # is cleared first.
    function Invoke-Step ([hashtable]$Arguments) {
        $global:LASTEXITCODE = 0
        $output = & $script:Step -RepoName demo -OrgName org -PullRequestId 7 @Arguments |
            Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Variable -Name MergePrTest -Scope Global -ErrorAction SilentlyContinue
}

Describe 'merge-pr.ps1' {
    It 'merges a pull request into the branch the nightly works on' {
        Set-PullRequest -Base rc
        (Invoke-Step @{ Branch = 'rc' }).ExitCode | Should -Be 0
        $global:MergePrTest.Merged | Should -BeTrue
    }

    It 'refuses a pull request into any other branch, and says why' {
        # A repository that takes changes through rc is worked on as rc, so a
        # pull request into its default branch is never merged by the nightly,
        # even when its id was given by hand.
        Set-PullRequest -Base main
        $result = Invoke-Step @{ Branch = 'rc' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "merges only into 'rc'"
        $global:MergePrTest.Merged | Should -BeFalse
    }

    It 'merges as before when it is not told the branch' {
        Set-PullRequest -Base main
        (Invoke-Step @{}).ExitCode | Should -Be 0
        $global:MergePrTest.Merged | Should -BeTrue
    }

    It 'merges nothing on a dry run, whatever the branch' {
        Set-PullRequest -Base main
        $result = Invoke-Step @{ Branch = 'rc'; DryRun = $true }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Dry run - not merging'
        $global:MergePrTest.Merged | Should -BeFalse
    }
}
