# Tests for steps/check-release-interval.ps1.
#
# The exit code is the decision. The output is checked where its wording tells
# a person what happened and what to do next. Tests of release tags build a
# throwaway git repository with dated commits and tags, and stand in for gh
# with a function that answers with the GitHub releases a test sets. The rule
# of one release a calendar month began on 19 November 2026, so most dates
# here come after it.

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

    # Stands in for gh, answering a release list as the --jq filter in the
    # check would, with one line of tag and publish date per release. A draft
    # is left out only with --exclude-drafts, as gh does.
    function global:gh {
        $global:GhCalls += , ($args -join ' ')
        foreach ($release in $global:Releases) {
            if ($release.Draft -and $args -contains '--exclude-drafts') { continue }
            "$($release.Tag)`t$($release.Published)"
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
}

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
    $env:ALLOW_EARLY_RELEASE = $null
    $env:WEEKLY_RELEASES_FROM = $null
}

Describe 'from 19 November 2026, when the rule began' {
    It 'does not count a release from before the rule began' {
        # The 4.6 releases are the first under the rule, whenever the last
        # 4.5 release went.
        $result = Invoke-Check @{
            LastRelease = '2026-11-10T09:00:00Z'; LastReleaseName = '4.5.120'
            Now = '2026-11-20T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'The last release, 4\.5\.120, was on 10 November 2026'
        $result.Output | Should -Match 'before the rule of one release a calendar month began on 19 November 2026'
    }

    It 'counts a release on the day the rule began' {
        $result = Invoke-Check @{
            LastRelease = '2026-11-19T08:00:00Z'; Now = '2026-11-25T09:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'the next may go from 1 December 2026'
    }

    It 'applies whatever WEEKLY_RELEASES_FROM says, as that variable is no longer read' {
        $env:WEEKLY_RELEASES_FROM = '2027-06-01'
        (Invoke-Check @{
            LastRelease = '2026-12-02T09:00:00Z'; Now = '2026-12-04T09:00:00Z' }
        ).ExitCode | Should -Be 1
    }
}

Describe 'with the date of the last release given' {
    It 'passes when nothing has been released before' {
        $result = Invoke-Check @{ LastRelease = ''; Now = '2026-12-04T10:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'first release'
    }

    It 'passes on the first day of the next calendar month, whatever the time of day' {
        $result = Invoke-Check @{
            LastRelease = '2026-12-31T23:59:00Z'; Now = '2027-01-01T00:01:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'the next may go from 1 January 2027'
    }

    It 'passes in the next calendar month even a few days later' {
        (Invoke-Check @{
            LastRelease = '2026-12-30T09:00:00Z'; Now = '2027-01-02T09:00:00Z' }
        ).ExitCode | Should -Be 0
    }

    It 'refuses later in the same calendar month, naming the last release and the first day the next may go' {
        $result = Invoke-Check @{
            LastRelease = '2026-12-01T00:01:00Z'; LastReleaseName = 'pull request #95'
            Now = '2026-12-31T23:59:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Released already this calendar month'
        $result.Output | Should -Match 'The last release, pull request #95, was on 1 December 2026'
        $result.Output | Should -Match 'the next may go from 1 January 2027'
    }

    It 'gives the first day of the next year after a release in December' {
        $result = Invoke-Check @{
            LastRelease = '2026-12-15T09:00:00Z'; Now = '2026-12-20T09:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'on or after 1 January 2027'
    }

    It 'refuses a last release dated after today, and says the date is wrong' {
        $result = Invoke-Check @{
            LastRelease = '2027-01-20T09:00:00Z'; Now = '2026-12-04T17:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'dated after today'
    }

    It 'allows an extra release when ALLOW_EARLY_RELEASE is set' {
        $env:ALLOW_EARLY_RELEASE = 'true'
        $result = Invoke-Check @{
            LastRelease = '2026-12-02T09:00:00Z'; Now = '2026-12-04T09:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Extra release this month'
    }

    It 'is not talked round by any other value of ALLOW_EARLY_RELEASE' {
        $env:ALLOW_EARLY_RELEASE = 'yes'
        (Invoke-Check @{
            LastRelease = '2026-12-02T09:00:00Z'; Now = '2026-12-04T09:00:00Z' }
        ).ExitCode | Should -Be 1
    }

    It 'says that an extra release needs permission for that one release, and how to give it' {
        $result = Invoke-Check @{
            LastRelease = '2026-12-02T09:00:00Z'; Now = '2026-12-04T09:00:00Z'
            HowToAllow = 'add the label.' }
        $result.Output | Should -Match 'needs permission for that one release\. With it, add the label\.'
        $result.Output | Should -Match 'on or after 1 January 2027'
        $result.Output | Should -Match 'CONTRIBUTING\.md#releasing-at-most-once-a-month'
    }

    It 'counts months in UTC' {
        # 23:30 on 30 November in New York is 04:30 on 1 December in UTC.
        $result = Invoke-Check @{
            LastRelease = '2026-11-30T23:30:00-05:00'; Now = '2026-12-15T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'was on 1 December 2026'
    }

    It 'stops on a date it cannot read' {
        { & $script:Check -LastRelease 'last Tuesday' -Now '2026-12-04T10:00:00Z' } |
            Should -Throw '*not a date and time*'
    }

    It 'stops when told nothing about the last release, rather than passing' {
        { & $script:Check -Now '2026-12-04T10:00:00Z' } | Should -Throw '*Give -RepoName*'
    }
}

Describe 'with the last release read from the tags of a checkout' {
    It 'passes when there are no version tags' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'examples-assets'; Commit = '2026-12-03T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-04T10:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'first release'
    }

    It 'does not count a tag from before the rule began' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.5.120'; Commit = '2026-11-10T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-11-25T10:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'before the rule'
    }

    It 'dates a lightweight tag by its GitHub release rather than its commit' {
        # Merged on the evening of 30 November and published by the nightly
        # on 1 December. Counted from the commit, December would be free.
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.0'; Commit = '2026-11-30T19:30:00Z' })
        $global:Releases = @(@{ Tag = '4.6.0'; Published = '2026-12-01T02:48:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; Repository = '51Degrees/example'
            Now = '2026-12-10T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'by its GitHub release'
        $result.Output | Should -Match 'The last release, 4\.6\.0, was on 1 December 2026'
        $result.Output | Should -Match 'the next may go from 1 January 2027'
        $global:GhCalls[0] | Should -Match 'release list -R 51Degrees/example'
    }

    It 'leaves out a draft release' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.0'; Commit = '2026-11-30T19:30:00Z' })
        $global:Releases = @(@{
            Tag = '4.6.0'; Published = '2026-12-01T02:48:00Z'; Draft = $true })
        $result = Invoke-Check @{
            RepoName = $script:Repo; Repository = '51Degrees/example'
            Now = '2026-12-10T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'by its commit'
    }

    It 'dates a lightweight tag with no GitHub release by its commit' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.0'; Commit = '2026-11-30T19:30:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-10T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'by its commit'
    }

    It 'dates an annotated tag by when it was made' {
        $script:Repo = New-TaggedRepo @(@{
            Name = 'pipeline/4.6.1'; Commit = '2026-11-20T10:00:00Z'
            Tagged = '2026-12-02T11:07:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-09T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'by its tag'
        $result.Output | Should -Match 'was on 2 December 2026'
    }

    It 'takes the newest release of any package when no prefix is given' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'caching/4.6.2'; Commit = '2026-11-20T10:00:00Z' },
            @{ Name = 'device-detection/4.6.180'; Commit = '2026-12-02T10:00:00Z' },
            @{ Name = 'common/5.1.8'; Commit = '2026-11-25T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'The last release, device-detection/4\.6\.180'
    }

    It 'counts only one package''s releases with -TagPrefix' {
        # Another package released yesterday. This one last released in
        # November, so it may go.
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'caching/4.6.2'; Commit = '2026-11-28T10:00:00Z' },
            @{ Name = 'device-detection/4.6.180'; Commit = '2026-12-07T10:00:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; TagPrefix = 'caching'; Now = '2026-12-08T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'caching/4\.6\.2'
    }

    It 'does not take a longer package name as the prefix''s own' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'fiftyone_pipeline_core/4.6.41'; Commit = '2026-11-25T10:00:00Z' },
            @{ Name = 'fiftyone_pipeline_core_extra/4.6.41'; Commit = '2026-12-07T10:00:00Z' })
        (Invoke-Check @{
            RepoName = $script:Repo; TagPrefix = 'fiftyone_pipeline_core'
            Now = '2026-12-08T12:00:00Z' }
        ).ExitCode | Should -Be 0
    }

    It 'reads a Go module''s tags with -TagPrefix' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'pipeline/v4.6.171'; Commit = '2026-12-07T10:00:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; TagPrefix = 'pipeline'; Now = '2026-12-08T12:00:00Z' }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'The last release, pipeline/v4\.6\.171'
    }

    It 'does not count a pre-release as a release' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.28'; Commit = '2026-11-20T10:00:00Z' },
            @{ Name = '4.6.29-bug-77-ci-fail-fast-setup.1'; Commit = '2026-12-07T10:00:00Z' })
        $result = Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z' }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'The last release, 4\.6\.28,'
    }

    It 'counts a tag with build metadata' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.49+2'; Commit = '2026-12-07T10:00:00Z' })
        (Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z' }
        ).ExitCode | Should -Be 1
    }

    It 'ignores tags that are not versions' {
        $script:Repo = New-TaggedRepo @(
            @{ Name = '4.6.90'; Commit = '2026-11-20T10:00:00Z' },
            @{ Name = 'examples-assets-v1.0.0'; Commit = '2026-12-07T10:00:00Z' })
        (Invoke-Check @{ RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z' }
        ).ExitCode | Should -Be 0
    }
}

Describe 'several packages, with -Plan' {
    BeforeEach {
        # caching and the Go module pipeline last released in November, and
        # dd on 7 December, the day before 'Now'.
        $script:Repo = New-TaggedRepo @(
            @{ Name = 'caching/4.6.2'; Commit = '2026-11-29T10:00:00Z' },
            @{ Name = 'pipeline/v4.6.171'; Commit = '2026-11-30T10:00:00Z' },
            @{ Name = 'dd/4.6.180'; Commit = '2026-12-07T10:00:00Z' })
    }

    It 'passes when every package last released in an earlier calendar month' {
        $result = Invoke-Check @{
            RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z'; Plan = @(
                [pscustomobject]@{ Name = 'caching'; Version = '4.6.3' }
                [pscustomobject]@{ Name = 'pipeline'; Version = '4.6.172' }) }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'caching/4\.6\.2'
        $result.Output | Should -Match 'pipeline/v4\.6\.171'
    }

    It 'refuses when any package was released this calendar month, naming those refused' {
        $result = Invoke-Check @{
            RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z'
            HowToAllow = 'add the label.'; Plan = @(
                [pscustomobject]@{ Name = 'caching'; Version = '4.6.3' }
                [pscustomobject]@{ Name = 'dd'; Version = '4.6.181' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'With it, add the label\.'
        $result.Output | Should -Match 'The last release, dd/4\.6\.180, was on 7 December 2026'
        $result.Output | Should -Match 'already released this calendar month: dd\.'
    }

    It 'allows an extra release of every package when ALLOW_EARLY_RELEASE is set' {
        $env:ALLOW_EARLY_RELEASE = 'true'
        (Invoke-Check @{
            RepoName = $script:Repo; Now = '2026-12-08T12:00:00Z'; Plan = @(
                [pscustomobject]@{ Name = 'dd'; Version = '4.6.181' }) }
        ).ExitCode | Should -Be 0
    }

    It 'dates each package by its GitHub release' {
        $global:Releases = @(@{ Tag = 'caching/4.6.2'; Published = '2026-12-04T02:48:00Z' })
        $result = Invoke-Check @{
            RepoName = $script:Repo; Repository = '51Degrees/example'
            Now = '2026-12-08T12:00:00Z'; Plan = @(
                [pscustomobject]@{ Name = 'caching'; Version = '4.6.3' }) }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'by its GitHub release'
    }

    It 'passes a plan with nothing in it' {
        $result = Invoke-Check @{ RepoName = $script:Repo; Plan = @() }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'nothing to check'
    }

    It 'stops when given a plan and a prefix' {
        { & $script:Check -RepoName $script:Repo -TagPrefix 'dd' -Plan @(
            [pscustomobject]@{ Name = 'dd' }) } |
            Should -Throw '*Give -Plan with -RepoName*'
    }

    It 'stops on a misspelt parameter, rather than checking without it' {
        { & $script:Check -RepoName $script:Repo -TagPrefx 'dd' } |
            Should -Throw '*TagPrefx*'
    }
}

}
