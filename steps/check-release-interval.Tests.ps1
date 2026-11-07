# Tests for steps/check-release-interval.ps1.
#
# The exit code is the decision. The output is checked where its wording tells
# a person what happened and what to do next. Tests of release tags build a
# throwaway git repository with dated commits and tags, and stand in for gh
# with a function that answers with the GitHub releases a test sets.

BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'check-release-interval.ps1'

    # Runs the check and returns its exit code and output together.
    function Invoke-Check ([hashtable]$Arguments) {
        $output = & $script:Check @Arguments | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    # A repository with one commit per tag. Each tag is a hashtable of Name,
    # Commit (the commit's date) and, for an annotated tag, Tagged (the date
    # the tag was made).
    function New-TaggedRepo ([hashtable[]]$Tags) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        foreach ($tag in $Tags) {
            $env:GIT_COMMITTER_DATE = $tag.Commit
            git -C $path -c user.name=test -c user.email=test@example.com `
                commit --quiet --allow-empty -m $tag.Name
            if ($tag.Tagged) {
                $env:GIT_COMMITTER_DATE = $tag.Tagged
                git -C $path -c user.name=test -c user.email=test@example.com `
                    tag -a $tag.Name -m $tag.Name
            } else {
                git -C $path tag $tag.Name
            }
        }
        $env:GIT_COMMITTER_DATE = $null
        return $path
    }

    # Stands in for gh, answering a releases request as the --jq filter in the
    # check would, with one line of tag, publish date and draft per release.
    function global:gh {
        $global:GhCalls += , ($args -join ' ')
        foreach ($release in $global:Releases) {
            $draft = ([bool]$release.Draft).ToString().ToLowerInvariant()
            "$($release.Tag)`t$($release.Published)`t$draft"
        }
    }
}

AfterAll {
    Remove-Item function:global:gh -ErrorAction SilentlyContinue
}

Describe 'check-release-interval.ps1' {

BeforeEach {
    $global:Releases = @()
    $global:GhCalls = @()
    # The rule applies unless a test says otherwise.
    $env:WEEKLY_RELEASES_FROM = '2026-01-01'
}

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
    $env:ALLOW_EARLY_RELEASE = $null
    $env:WEEKLY_RELEASES_FROM = $null
}

Describe 'with the date the rule starts from in WEEKLY_RELEASES_FROM' {
    # Each release here comes two days after the last, which the rule refuses.

    It 'reports and passes when the variable is not set' {
        $env:WEEKLY_RELEASES_FROM = $null
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Weekly release rule not enforced'
        $result.Output | Should -Match 'would be refused'
        $result.Output | Should -Match 'WEEKLY_RELEASES_FROM is not set'
    }

    It 'reports and passes before a date still ahead' {
        $env:WEEKLY_RELEASES_FROM = '2026-11-10'
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'not enforced until 10 November 2026'
    }

    It 'refuses from a date already past' {
        $env:WEEKLY_RELEASES_FROM = '2026-11-03'
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'applies from 3 November 2026'
    }

    It 'refuses on the date itself' {
        $env:WEEKLY_RELEASES_FROM = '2026-11-06'
        (Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        ).ExitCode | Should -Be 1
    }

    It 'follows a repository''s own later date over the organisation''s' {
        # GitHub gives a workflow the repository's variable in place of the
        # organisation's of the same name, so a repository still moving can
        # start later than the organisation's 3 November.
        $env:WEEKLY_RELEASES_FROM = '2026-12-01'
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'not enforced until 1 December 2026'
    }

    It 'stops on a value it cannot read, naming the variable' {
        $env:WEEKLY_RELEASES_FROM = 'soon'
        { & $script:Check -LastRelease '2026-11-04T09:00:00Z' -Now '2026-11-06T09:00:00Z' } |
            Should -Throw "*WEEKLY_RELEASES_FROM is 'soon'*"
    }
}

Describe 'with the date of the last release given' {
    It 'passes when nothing has been released before' {
        $result = Invoke-Check @{ LastRelease = ''; Now = '2026-11-04T10:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'first release'
    }

    It 'passes exactly seven calendar days later, whatever the time of day' {
        # A release late on 4 November allows the next early on 11 November.
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T23:59:00Z'; Now = '2026-11-11T00:01:00Z' }
        $result.ExitCode | Should -Be 0
    }

    It 'refuses six days later, whatever the time of day' {
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T00:01:00Z'; LastReleaseName = 'pull request #95'
            Now = '2026-11-10T23:59:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Released less than a week ago'
        $result.Output | Should -Match 'The last release, pull request #95, was on 4 November 2026'
        $result.Output | Should -Match 'the next may go from 11 November 2026'
    }

    It 'refuses on the same day' {
        (Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-04T17:00:00Z' }
        ).ExitCode | Should -Be 1
    }

    It 'refuses a last release dated after today, and says the date is wrong' {
        $result = Invoke-Check @{
            LastRelease = '2026-11-20T09:00:00Z'; Now = '2026-11-04T17:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'dated after today'
    }

    It 'allows an early release when ALLOW_EARLY_RELEASE is set' {
        $env:ALLOW_EARLY_RELEASE = 'true'
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Early release'
    }

    It 'is not talked round by any other value of ALLOW_EARLY_RELEASE' {
        $env:ALLOW_EARLY_RELEASE = 'yes'
        (Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z' }
        ).ExitCode | Should -Be 1
    }

    It 'says how to release early, and whose permission that needs' {
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T09:00:00Z'; Now = '2026-11-06T09:00:00Z'
            HowToAllow = 'add the label.' }
        $result.Output | Should -Match "needs James Rosewell's permission. With it, add the label\."
        $result.Output | Should -Match 'on or after 11 November 2026'
    }

    It 'counts days in UTC' {
        # 23:30 on 4 November in New York is 04:30 on 5 November in UTC.
        $result = Invoke-Check @{
            LastRelease = '2026-11-04T23:30:00-05:00'; Now = '2026-11-11T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'was on 5 November 2026'
    }

    It 'stops on a date it cannot read' {
        { & $script:Check -LastRelease 'last Tuesday' -Now '2026-11-04T10:00:00Z' } |
            Should -Throw '*not a date and time*'
    }

    It 'stops when told nothing about the last release, rather than passing' {
        { & $script:Check -Now '2026-11-04T10:00:00Z' } | Should -Throw '*Give -RepoName*'
    }
}

Describe 'with the last release read from the tags of a checkout' {
    It 'passes when there are no version tags' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'examples-assets'; Commit = '2026-11-03T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-04T10:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'first release'
    }

    It 'dates a lightweight tag by its GitHub release rather than its commit' {
        # Merged on the evening of 3 November and published by the nightly on
        # 4 November. Counted from the commit, 10 November would be a week.
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.5.102'; Commit = '2026-11-03T19:30:00Z' })
        $global:Releases = @(@{ Tag = '4.5.102'; Published = '2026-11-04T02:48:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; Repository = '51Degrees/example'
            Now = '2026-11-10T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'by its GitHub release'
        $result.Output | Should -Match 'The last release, 4\.5\.102, was on 4 November 2026'
        $global:GhCalls[0] | Should -Match 'repos/51Degrees/example/releases'
    }

    It 'leaves out a draft release' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.5.102'; Commit = '2026-11-03T19:30:00Z' })
        $global:Releases = @(@{
            Tag = '4.5.102'; Published = '2026-11-04T02:48:00Z'; Draft = $true })
        $result = Invoke-Check @{
            RepoName = $script:Repo; Repository = '51Degrees/example'
            Now = '2026-11-10T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'by its commit'
    }

    It 'dates a lightweight tag with no GitHub release by its commit' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.5.102'; Commit = '2026-11-03T19:30:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-10T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'by its commit'
    }

    It 'dates an annotated tag by when it was made' {
        $script:Repo = New-TaggedRepo @(@{
            Name = 'pipeline/4.5.128'; Commit = '2026-10-20T10:00:00Z'
            Tagged = '2026-11-03T11:07:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-09T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'by its tag'
        $result.Output | Should -Match 'was on 3 November 2026'
    }

    It 'takes the newest release of any package when no prefix is given' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'caching/4.5.2'; Commit = '2026-10-01T10:00:00Z' },
            @{ Name = 'device-detection/4.5.180'; Commit = '2026-11-02T10:00:00Z' },
            @{ Name = 'common/5.1.8'; Commit = '2026-10-15T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-08T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'The last release, device-detection/4\.5\.180'
    }

    It 'counts only one package''s releases with -TagPrefix' {
        # Another package released yesterday. This one last released eight
        # days ago, so it may go.
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'caching/4.5.2'; Commit = '2026-10-31T10:00:00Z' },
            @{ Name = 'device-detection/4.5.180'; Commit = '2026-11-07T10:00:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; TagPrefix = 'caching'; Now = '2026-11-08T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'caching/4\.5\.2'
    }

    It 'does not take a longer package name as the prefix''s own' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'fiftyone_pipeline_core/4.5.41'; Commit = '2026-10-20T10:00:00Z' },
            @{ Name = 'fiftyone_pipeline_core_extra/4.5.41'; Commit = '2026-11-07T10:00:00Z' })
        (Invoke-Check @{
            RepoName = $script:Repo; TagPrefix = 'fiftyone_pipeline_core'
            Now = '2026-11-08T12:00:00Z' }
        ).ExitCode | Should -Be 0
    }

    It 'ignores tags that are not versions' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.5.90'; Commit = '2026-10-01T10:00:00Z' },
            @{ Name = 'examples-assets-v1.0.0'; Commit = '2026-11-07T10:00:00Z' })
        (Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-08T12:00:00Z' }
        ).ExitCode | Should -Be 0
    }
}

}
