# Tests for steps/get-caller-ci-secrets.ps1. Run with: Invoke-Pester ./steps/get-caller-ci-secrets.Tests.ps1
#
# The step asks GitHub for the calling repository's ci/ci-secrets.psd1 at a
# branch and saves it for steps/export-secrets.ps1, so `gh` is replaced by a
# function that answers for the repository each test describes, and no test
# reaches GitHub. Each test saves to a file of its own.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'get-caller-ci-secrets.ps1'
    $script:Export = Join-Path $PSScriptRoot 'export-secrets.ps1'
    $script:Ci = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'ci-secrets.psd1')

    # A list holding the names given, as a calling repository writes it.
    function New-List ([string[]]$Names) {
        $quoted = ($Names | ForEach-Object { "        '$_'" }) -join "`n"
        return "@{`n    Scripts = @(`n$quoted`n    )`n}"
    }

    # The repository `gh` answers for. It holds the list given, or with
    # -Failure it has none to give and `gh` fails with that message. Global,
    # because the step calls `gh` from its own script scope.
    function Set-Repository ([string]$Content, [string]$Failure) {
        $global:CallerCiSecretsTest = @{
            Content = $Content
            Failure = $Failure
            Calls = @()
        }
    }

    # Stands in for gh, recording each call as its list of arguments. Like
    # gh, it writes the file a line at a time, and on a failure it sets a
    # non-zero exit code and gives the message only to the call that keeps
    # the error stream, the one with --jq.
    function gh {
        $test = $global:CallerCiSecretsTest
        $test.Calls += , @($args)
        if ($args[0] -ne 'api') { throw "Unexpected call: gh $args" }
        if (-not $test.Failure) {
            $global:LASTEXITCODE = 0
            return $test.Content -split "`n"
        }
        $global:LASTEXITCODE = 1
        if ($args -contains '--jq') { return $test.Failure }
    }

    # Runs the step for the repository org/demo. Every stream, so that the
    # output checks see all the step writes.
    function Invoke-Step ([string]$Ref = 'rc') {
        return (& $script:Step -Repository org/demo -Ref $Ref -Path $script:Saved *>&1 | Out-String)
    }
}

AfterAll {
    Remove-Variable -Name CallerCiSecretsTest -Scope Global -ErrorAction SilentlyContinue
}

Describe 'get-caller-ci-secrets.ps1' {

    BeforeEach {
        $script:Saved = Join-Path ([IO.Path]::GetTempPath()) "get-caller-ci-secrets-tests-$(New-Guid).psd1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Saved -Force -ErrorAction SilentlyContinue
    }

    It 'asks for ci/ci-secrets.psd1 in the repository at the branch given' {
        Set-Repository -Content (New-List 'EXAMPLE_TOKEN')
        Invoke-Step -Ref rc | Out-Null
        $calls = $global:CallerCiSecretsTest.Calls
        $calls.Count | Should -Be 1
        $calls[0][0] | Should -Be 'api'
        $calls[0] | Should -Contain 'repos/org/demo/contents/ci/ci-secrets.psd1?ref=rc'
    }

    It 'escapes the branch name in the request' {
        Set-Repository -Content (New-List 'EXAMPLE_TOKEN')
        Invoke-Step -Ref version/4.4 | Out-Null
        $global:CallerCiSecretsTest.Calls[0] | Should -Contain 'repos/org/demo/contents/ci/ci-secrets.psd1?ref=version%2F4.4'
    }

    It 'saves the list as the repository holds it' {
        $content = New-List 'EXAMPLE_TOKEN', 'EXAMPLE_KEY'
        Set-Repository -Content $content
        Invoke-Step | Out-Null
        ((Get-Content -LiteralPath $script:Saved) -join "`n") | Should -Be $content
        (Import-PowerShellDataFile -LiteralPath $script:Saved).Scripts | Should -Be @('EXAMPLE_TOKEN', 'EXAMPLE_KEY')
    }

    It 'writes the repository, the branch and the names listed to its output' {
        Set-Repository -Content (New-List 'EXAMPLE_TOKEN', 'EXAMPLE_KEY')
        $output = Invoke-Step -Ref rc
        $output | Should -Match ([regex]::Escape('org/demo lists 2 CI secret(s) of its own at rc: EXAMPLE_TOKEN, EXAMPLE_KEY'))
    }

    It 'saves a list with no names and counts none' {
        Set-Repository -Content '@{}'
        $output = Invoke-Step
        $output | Should -Match ([regex]::Escape('lists 0 CI secret(s)'))
        Test-Path -LiteralPath $script:Saved -PathType Leaf | Should -BeTrue
    }

    It 'saves nothing and does not fail when the repository has no list' {
        Set-Repository -Failure 'gh: Not Found (HTTP 404)'
        { Invoke-Step -Ref rc } | Should -Not -Throw
        Test-Path -LiteralPath $script:Saved | Should -BeFalse
        $global:LASTEXITCODE | Should -Be 0 -Because 'the step that follows starts from a clean exit code'
    }

    It 'removes a file already at the path when the repository has no list' {
        Set-Content -LiteralPath $script:Saved -Value (New-List 'EXAMPLE_TOKEN')
        Set-Repository -Failure 'gh: Not Found (HTTP 404)'
        Invoke-Step -Ref rc | Out-Null
        Test-Path -LiteralPath $script:Saved | Should -BeFalse -Because 'the export step then finds no list'
    }

    It 'says that the repository has no list' {
        Set-Repository -Failure 'gh: Not Found (HTTP 404)'
        Invoke-Step -Ref rc | Should -Match ([regex]::Escape('org/demo lists no CI secrets of its own at rc.'))
    }

    It 'stops with the message, saving nothing, on any other failure' {
        Set-Repository -Failure 'gh: Bad Gateway (HTTP 502)'
        { Invoke-Step } | Should -Throw -ExpectedMessage '*HTTP 502*'
        Test-Path -LiteralPath $script:Saved | Should -BeFalse
    }

    It 'stops on a list that is not a PowerShell data file' {
        foreach ($content in "@{`n    Scripts = @(`n        'EXAMPLE_TOKEN'", '@{ Scripts = @(Get-Date) }', 'EXAMPLE_TOKEN') {
            Set-Repository -Content $content
            { Invoke-Step } | Should -Throw -Because "this is not a data file: $content"
        }
    }

    # The step saves the list as it is. The export step reads it and decides
    # which names it takes.
    Context 'with the export step' {

        BeforeEach {
            $script:SavedGitHubEnv = $env:GITHUB_ENV
            $env:GITHUB_ENV = $null
            # A caller's own name, held in a variable as the export tests hold
            # theirs.
            $script:Listed = 'EXAMPLE_TOKEN'
        }

        AfterEach {
            $env:GITHUB_ENV = $script:SavedGitHubEnv
            Remove-Item -Path "Env:$script:Listed" -ErrorAction SilentlyContinue
        }

        It 'saves a list the export step takes' {
            Set-Repository -Content (New-List $script:Listed)
            Invoke-Step | Out-Null
            $secrets = @{ $script:Listed = 'value-example-token-5e2a' } | ConvertTo-Json -Compress
            & $script:Export -Secrets $secrets -Vars '{}' -CallerList $script:Saved *>&1 | Out-Null
            (Get-Item -Path "Env:$script:Listed").Value | Should -Be 'value-example-token-5e2a'
        }

        It 'saves a publishing, signing or _51DEGREES_ name as listed, and the export step refuses it' {
            foreach ($name in $script:Ci.Publish[0], $script:Ci.Sign[0], '_51DEGREES_EXAMPLE_KEY') {
                Set-Repository -Content (New-List $name)
                { Invoke-Step } | Should -Not -Throw
                (Import-PowerShellDataFile -LiteralPath $script:Saved).Scripts | Should -Be @($name)
                $secrets = @{ $name = 'value-example-5e2a' } | ConvertTo-Json -Compress
                { & $script:Export -Secrets $secrets -Vars '{}' -CallerList $script:Saved *>&1 | Out-Null } |
                    Should -Throw "*may list only*$name*"
            }
        }
    }
}
