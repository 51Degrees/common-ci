# Tests for steps/checkout-pr.ps1.
#
# The nightly selects a pull request at a head commit and builds that commit.
# If the head is a different commit when the build checks it out, nothing is
# built. Functions stand in for gh and git, so no test reaches GitHub or
# changes a repository.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'checkout-pr.ps1'
    $script:Selected = 'a' * 40
    $script:Other = 'b' * 40

    function global:gh {
        $request = $args -join ' '
        $global:CheckoutCalls += , "gh $request"
        if ($request -match '^pr view .*headRefOid') { return $global:LiveHead }
        if ($request -match '^pr view ') { return '#7 feature->rc : A change' }
        if ($request -match '^pr checkout ') { return }
        throw "Unexpected call: gh $request"
    }

    function global:git {
        $request = $args -join ' '
        $global:CheckoutCalls += , "git $request"
        if ($request -eq 'rev-parse HEAD') { return $global:LiveHead }
    }

    # Runs the step for pull request 7 in a folder of its own and returns its
    # result, the variable it set and whether it threw.
    function Invoke-Step ([string]$HeadSha) {
        $global:CheckoutCalls = @()
        $root = Join-Path ([IO.Path]::GetTempPath()) "checkout-pr-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path (Join-Path $root 'demo') -Force | Out-Null
        Push-Location $root
        try {
            $arguments = @{ RepoName = 'demo'; PullRequestId = 7; Branch = 'rc'; SetVariable = 'CheckedOut' }
            if ($HeadSha) { $arguments.HeadSha = $HeadSha }
            $CheckedOut = $null
            $threw = $null
            try { & $script:Step @arguments 6>$null | Out-Null } catch { $threw = $_ }
            [pscustomobject]@{ Sha = $CheckedOut; Error = $threw; Calls = $global:CheckoutCalls }
        } finally {
            Pop-Location
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }
}

AfterAll {
    # Function:\ removes them; a path naming the global scope removes nothing.
    Remove-Item Function:\gh, Function:\git -ErrorAction SilentlyContinue
    'CheckoutCalls', 'LiveHead' | ForEach-Object { Remove-Variable -Name $_ -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'checkout-pr.ps1 with the head commit fixed at selection' {
    It 'builds the selected commit when it is the head' {
        $global:LiveHead = $script:Selected
        $result = Invoke-Step -HeadSha $script:Selected
        $result.Error | Should -BeNullOrEmpty
        $result.Sha | Should -Be $script:Selected
    }

    It 'stops when the head is a different commit' {
        $global:LiveHead = $script:Other
        $result = Invoke-Step -HeadSha $script:Selected
        $result.Error | Should -Not -BeNullOrEmpty
        "$($result.Error)" | Should -Match 'not the selected'
    }

    It 'stops before it merges anything in, when the head is a different commit' {
        $global:LiveHead = $script:Other
        $result = Invoke-Step -HeadSha $script:Selected
        $result.Calls | Should -Not -Contain 'git merge origin/rc'
    }

    It 'reports the selected commit, not the live head, as the one built' {
        $global:LiveHead = $script:Selected
        $result = Invoke-Step -HeadSha $script:Selected
        $result.Calls | Where-Object { $_ -match 'headRefOid' } | Should -BeNullOrEmpty
    }
}
