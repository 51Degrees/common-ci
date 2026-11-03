# Tests for steps/get-target-branch.ps1.
#
# The step asks GitHub for the repository's default branch and whether it has
# an rc branch, so `gh` is replaced by a function that answers for the
# repository each test describes. Callers assign the output to a variable, so
# the tests also check that the branch name is the only thing written to it.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'get-target-branch.ps1'

    # The repository `gh` answers for. Global, because the step calls `gh`
    # from its own script scope.
    function Set-Repository ([string]$Default, [string[]]$Branches, [switch]$Unreachable) {
        $global:TargetBranchRepository = @{
            Default = $Default
            Branches = $Branches
            Unreachable = [bool]$Unreachable
        }
    }

    function gh {
        $repository = $global:TargetBranchRepository
        if ($repository.Unreachable) {
            throw 'gh: Bad Gateway (HTTP 502)'
        }
        switch ($args[1]) {
            'repos/org/demo' {
                return '{"default_branch":"' + $repository.Default + '"}'
            }
            'repos/org/demo/git/matching-refs/heads/rc' {
                # GitHub answers with every branch whose name starts with rc.
                $refs = @($repository.Branches | Where-Object { $_ -like 'rc*' } |
                    ForEach-Object { '{"ref":"refs/heads/' + $_ + '"}' })
                return '[' + ($refs -join ',') + ']'
            }
            default { throw "Unexpected call: gh $args" }
        }
    }

    function Invoke-Step ([string]$Branch) {
        @(& $script:Step -RepoName demo -OrgName org -Branch $Branch)
    }
}

AfterAll {
    Remove-Variable -Name TargetBranchRepository -Scope Global -ErrorAction SilentlyContinue
}

Describe 'get-target-branch.ps1' {
    It 'answers rc for the default branch of a repository with rc' {
        Set-Repository -Default main -Branches main, rc
        Invoke-Step main | Should -Be 'rc'
    }

    It 'answers the default branch where the repository has no rc' {
        Set-Repository -Default main -Branches main, feature/thing
        Invoke-Step main | Should -Be 'main'
    }

    It 'does not take a branch whose name only starts with rc for rc' {
        Set-Repository -Default main -Branches main, rc-old, rcx
        Invoke-Step main | Should -Be 'main'
    }

    It 'leaves a branch other than the default as it is' {
        # A version branch keeps its own pull requests.
        Set-Repository -Default main -Branches main, rc, version/4.4
        Invoke-Step version/4.4 | Should -Be 'version/4.4'
    }

    It 'leaves rc as rc' {
        Set-Repository -Default main -Branches main, rc
        Invoke-Step rc | Should -Be 'rc'
    }

    It 'answers rc whatever the default branch is called' {
        Set-Repository -Default master -Branches master, rc
        Invoke-Step master | Should -Be 'rc'
    }

    It 'fails rather than answering the default branch when GitHub cannot be asked' {
        # Answering main here would let the nightly merge into main in a
        # repository that takes its changes through rc.
        Set-Repository -Default main -Branches main, rc -Unreachable
        { Invoke-Step main } | Should -Throw
    }

    It 'writes nothing but the branch name, so a caller can assign it' {
        Set-Repository -Default main -Branches main, rc
        $output = Invoke-Step main
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType [string]
    }
}
