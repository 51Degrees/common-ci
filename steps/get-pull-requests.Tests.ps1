# Tests for steps/get-pull-requests.ps1.
#
# The nightly build runs a pull request's code with the organization's
# secrets. Code from a fork must never run with them, so a pull request whose
# head is in a fork is never selected, whatever its approvals, and that holds
# for pull request numbers given by hand too. Each selected pull request
# carries the head commit it was selected at, so the build and the merge can
# hold to that commit.
#
# A function stands in for gh. The script is dot-sourced, which only defines
# its functions.

BeforeAll {
    . (Join-Path $PSScriptRoot 'get-pull-requests.ps1') -RepoName 'example' -OrgName '51Degrees'

    $script:Head = 'b' * 40

    # The open pull requests gh lists, and the ones it describes one by one.
    function global:gh {
        $request = ($args | ForEach-Object { $_ -join ',' }) -join ' '
        $global:GhRequests += , $request
        if ($request -match '^pr list ') {
            @($global:Listed | Where-Object { -not $_.isDraft }) | ConvertTo-Json -Depth 5 -AsArray
        } elseif ($request -match '^pr view (?:-R \S+ )?(\d+) ') {
            $number = [int]$Matches[1]
            $pr = $global:Described[$number]
            if (-not $pr) { throw "No pull request $number" }
            $pr | ConvertTo-Json -Depth 5
        } else {
            throw "Unexpected request: $request"
        }
    }

    # writer has write access to the repository.
    $script:Collaborators = @(
        [pscustomobject]@{ login = 'writer'; permissions = [pscustomobject]@{ admin = $false; maintain = $false; push = $true } }
    )

    # A pull request as gh describes it. Leave out a field with -Without.
    function New-Pr ([int]$Number, [bool]$Fork = $false, [string]$Sha = $script:Head, [string]$Author = 'writer', [string[]]$Without = @()) {
        $pr = [ordered]@{
            number            = $Number
            isDraft           = $false
            isCrossRepository = $Fork
            headRefOid        = $Sha
            author            = @{ login = $Author }
            reviewRequests    = @()
            latestReviews     = @()
        }
        foreach ($field in $Without) { $pr.Remove($field) }
        [pscustomobject]$pr
    }

    function Set-Prs ([object[]]$Prs) {
        $global:Listed = @($Prs)
        $global:Described = @{}
        foreach ($pr in $Prs) { $global:Described[[int]$pr.number] = $pr }
        $global:GhRequests = @()
    }

    # The version directive check calls another script that asks gh about
    # labels. It is not what these tests are about, so it always agrees.
    function Test-VersionDirective { $true }
}

AfterAll {
    # Function:\ removes it; a path naming the global scope removes nothing.
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    'Listed', 'Described', 'GhRequests' | ForEach-Object { Remove-Variable -Name $_ -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'a pull request whose head is in a fork' {
    It 'is never selected from the open pull requests' {
        Set-Prs @((New-Pr -Number 5 -Fork $true))
        $selected = @(Get-PullRequests 6>$null)
        $selected.id | Should -Not -Contain 5
    }

    It 'is not selected even when someone with write access approved it' {
        $pr = New-Pr -Number 5 -Fork $true -Author 'outsider'
        $pr.latestReviews = @([pscustomobject]@{ author = @{ login = 'writer' }; state = 'APPROVED' })
        Set-Prs @($pr)
        @(Get-PullRequests 6>$null).id | Should -Not -Contain 5
    }

    It 'is not selected when its number is given by hand' {
        Set-Prs @((New-Pr -Number 5 -Fork $true))
        @(Get-PullRequests -Ids '5' 6>$null).id | Should -Not -Contain 5
    }

    It 'says in the log why it was skipped' {
        Set-Prs @((New-Pr -Number 5 -Fork $true))
        $log = Get-PullRequests 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | Out-String
        $log | Should -Match 'PR 5'
        $log | Should -Match 'fork'
    }

    It 'leaves the other pull requests selected' {
        Set-Prs @((New-Pr -Number 5 -Fork $true), (New-Pr -Number 6))
        @(Get-PullRequests 6>$null).id | Should -Be @(6)
    }
}

Describe 'the fields the rule relies on' {
    It 'asks gh whether the head is in a fork, and for the head commit' {
        Set-Prs @((New-Pr -Number 6))
        Get-PullRequests 6>$null | Out-Null
        ($global:GhRequests | Where-Object { $_ -match '^pr list ' }) | Should -Match 'isCrossRepository'
        ($global:GhRequests | Where-Object { $_ -match '^pr list ' }) | Should -Match 'headRefOid'
    }

    It 'does not select a pull request when gh does not say whether its head is in a fork' {
        Set-Prs @((New-Pr -Number 6 -Without 'isCrossRepository'))
        @(Get-PullRequests 6>$null).id | Should -Not -Contain 6
    }

    It 'does not select a pull request when gh gives no head commit' {
        Set-Prs @((New-Pr -Number 6 -Sha ''))
        @(Get-PullRequests 6>$null).id | Should -Not -Contain 6
    }

    It 'does the same for a number given by hand' {
        Set-Prs @((New-Pr -Number 6 -Without 'isCrossRepository'))
        @(Get-PullRequests -Ids '6' 6>$null).id | Should -Not -Contain 6
    }
}

Describe 'a selected pull request' {
    It 'carries the head commit it was selected at' {
        Set-Prs @((New-Pr -Number 6 -Sha ('c' * 40)))
        $selected = @(Get-PullRequests 6>$null)
        $selected.Count | Should -Be 1
        $selected[0].id | Should -Be 6
        $selected[0].sha | Should -Be ('c' * 40)
    }

    It 'carries its head commit when its number is given by hand' {
        Set-Prs @((New-Pr -Number 6 -Sha ('c' * 40)))
        $selected = @(Get-PullRequests -Ids '6' 6>$null)
        $selected[0].id | Should -Be 6
        $selected[0].sha | Should -Be ('c' * 40)
    }

    It 'takes several numbers given by hand' {
        Set-Prs @((New-Pr -Number 6), (New-Pr -Number 7))
        @(Get-PullRequests -Ids '6, 7' 6>$null).id | Should -Be @(6, 7)
    }

    It 'refuses a number given by hand that is not a number' {
        Set-Prs @((New-Pr -Number 6))
        { Get-PullRequests -Ids '6;whoami' 6>$null } | Should -Throw
    }

    It 'is pull request 0, the branch itself, with no commit, when nothing is selected' {
        Set-Prs @((New-Pr -Number 5 -Fork $true))
        $selected = @(Get-PullRequests 6>$null)
        $selected.Count | Should -Be 1
        $selected[0].id | Should -Be 0
        $selected[0].sha | Should -Be ''
    }

    It 'builds nothing, not the branch, when every number given by hand is refused' {
        Set-Prs @((New-Pr -Number 5 -Fork $true))
        @(Get-PullRequests -Ids '5' 6>$null).Count | Should -Be 0
    }

    It 'keeps a 0 given by hand as the branch itself' {
        Set-Prs @()
        $selected = @(Get-PullRequests -Ids '0' 6>$null)
        $selected[0].id | Should -Be 0
        $selected[0].sha | Should -Be ''
    }
}

Describe 'what stays as it was for a pull request from a branch in the repository' {
    It 'is selected when its author has write access' {
        Set-Prs @((New-Pr -Number 6))
        @(Get-PullRequests 6>$null).id | Should -Be @(6)
    }

    It 'is not selected when its author has no write access and nobody approved it' {
        Set-Prs @((New-Pr -Number 6 -Author 'outsider'))
        @(Get-PullRequests 6>$null).id | Should -Be @(0)
    }

    It 'leaves out a draft' {
        $draft = New-Pr -Number 6
        $draft.isDraft = $true
        Set-Prs @($draft)
        @(Get-PullRequests 6>$null).id | Should -Be @(0)
    }
}
