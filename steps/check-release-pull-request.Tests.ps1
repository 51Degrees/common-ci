# Tests for steps/check-release-pull-request.ps1.
#
# A function stands in for gh, answering as the --jq filters in the check
# would. Each test sets the labels on the pull request being checked and the
# closed pull requests from rc, and the exit code is the decision.

BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'check-release-pull-request.ps1'

    function global:gh {
        $request = $args -join ' '
        $global:GhCalls += , $request
        if ($request -match 'pulls/\d+ ') {
            $global:Labels
        } elseif ($request -match 'pulls\?') {
            foreach ($pr in $global:Closed) { "$($pr.Number)`t$($pr.MergedAt)" }
        } else {
            throw "Unexpected request: $request"
        }
    }

    # Runs the check on pull request 100 of 51Degrees/example and returns its
    # exit code and output together.
    function Invoke-Check ([string]$Now) {
        $output = & $script:Check -Repository '51Degrees/example' -PullRequest 100 `
            -DefaultBranch 'main' -RunUrl 'https://example.test/run' -Now $Now |
            Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Item function:global:gh -ErrorAction SilentlyContinue
}

Describe 'check-release-pull-request.ps1' {

BeforeEach {
    $global:Labels = @()
    $global:Closed = @()
    $global:GhCalls = @()
    # The rule applies unless a test says otherwise.
    $env:WEEKLY_RELEASES_FROM = '2026-01-01'
}

AfterEach {
    $env:ALLOW_EARLY_RELEASE = $null
    $env:WEEKLY_RELEASES_FROM = $null
}

It 'reports and passes a release two days after the last before the rule starts' {
    $env:WEEKLY_RELEASES_FROM = $null
    $global:Closed = @(@{ Number = 95; MergedAt = '2026-11-02T19:30:25Z' })
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match 'Weekly release rule not enforced'
}

It 'passes the first release from rc' {
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match 'first release'
}

It 'refuses a release two days after the last, and says how to ask for one' {
    $global:Closed = @(@{ Number = 95; MergedAt = '2026-11-02T19:30:25Z' })
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'The last release, pull request #95, was on 2 November 2026'
    $result.Output | Should -Match 'the next may go from 9 November 2026'
    $result.Output | Should -Match "James Rosewell's permission"
    $result.Output | Should -Match "add the label 'early-release' to this pull request"
    $result.Output | Should -Match 're-run this check from https://example\.test/run'
}

It 'passes a week after the last' {
    $global:Closed = @(@{ Number = 95; MergedAt = '2026-11-04T19:30:25Z' })
    (Invoke-Check '2026-11-11T08:00:00Z').ExitCode | Should -Be 0
}

It 'allows an early release when the label is on the pull request' {
    $global:Labels = @('type: bug', 'early-release')
    $global:Closed = @(@{ Number = 95; MergedAt = '2026-11-02T19:30:25Z' })
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match "The label 'early-release' is on pull request #100"
}

It 'is not allowed early by ALLOW_EARLY_RELEASE alone' {
    # Only the label allows it, so who allowed it is on the pull request.
    $env:ALLOW_EARLY_RELEASE = 'true'
    $global:Closed = @(@{ Number = 95; MergedAt = '2026-11-02T19:30:25Z' })
    (Invoke-Check '2026-11-04T10:00:00Z').ExitCode | Should -Be 1
}

It 'counts from the pull request merged last, in whatever order they come' {
    $global:Closed = @(
        @{ Number = 90; MergedAt = '2026-10-20T10:00:00Z' },
        @{ Number = 95; MergedAt = '2026-11-02T19:30:25Z' },
        @{ Number = 93; MergedAt = '2026-10-27T10:00:00Z' })
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'pull request #95'
}

It 'ignores pull requests closed without merging, and the one being checked' {
    $global:Closed = @(
        @{ Number = 96; MergedAt = '' },
        @{ Number = 100; MergedAt = '2026-11-03T10:00:00Z' },
        @{ Number = 90; MergedAt = '2026-10-20T10:00:00Z' })
    $result = Invoke-Check '2026-11-04T10:00:00Z'
    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match 'pull request #90'
}

It 'asks only for pull requests from the repository''s own rc into the default branch' {
    Invoke-Check '2026-11-04T10:00:00Z' | Out-Null
    $list = $global:GhCalls | Where-Object { $_ -match 'pulls\?' }
    $list | Should -Match 'state=closed'
    $list | Should -Match 'base=main'
    $list | Should -Match 'head=51Degrees:rc'
}

}
