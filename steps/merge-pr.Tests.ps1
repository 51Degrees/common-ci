# Tests for steps/merge-pr.ps1.
#
# `gh` is replaced by a function that describes one pull request and records
# whether the merge was asked for, and with what, so no test reaches GitHub.
#
# The merge names the head commit the pull request was selected and built at.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'merge-pr.ps1'

    # The pull request `gh` answers for. Global, because the step calls `gh`
    # from its own script scope.
    function Set-PullRequest ([string]$Base) {
        $global:MergePrTest = @{ Base = $Base; Merged = $false; Request = $null }
    }

    function gh {
        $test = $global:MergePrTest
        if ($args[0] -eq 'pr' -and $args[1] -eq 'view') {
            return '{"number":7,"headRefName":"update-submodules/' + $test.Base +
                '","baseRefName":"' + $test.Base + '","title":"Update submodules"}'
        }
        if ($args[0] -eq 'api' -and $args[1] -eq '/repos/org/demo/pulls/7/merge') {
            $test.Merged = $true
            $test.Request = $args -join ' '
            return '{"merged":true}'
        }
        throw "Unexpected call: gh $args"
    }

    # The step only sets an exit code when it refuses, so the last test's code
    # is cleared first. Every call names the head commit selected, unless the
    # test gives its own or sets it to an empty one.
    $script:Selected = 'a' * 40
    function Invoke-Step ([hashtable]$Arguments) {
        $global:LASTEXITCODE = 0
        if (-not $Arguments.ContainsKey('HeadSha')) { $Arguments.HeadSha = $script:Selected }
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

    It 'names the head commit selected in the merge' {
        Set-PullRequest -Base rc
        (Invoke-Step @{ Branch = 'rc' }).ExitCode | Should -Be 0
        $global:MergePrTest.Request | Should -Match "sha=$($script:Selected)"
    }

    It 'refuses to merge when no head commit was selected, and says why' {
        Set-PullRequest -Base rc
        $result = Invoke-Step @{ Branch = 'rc'; HeadSha = '' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'head commit'
        $global:MergePrTest.Merged | Should -BeFalse
    }
}
