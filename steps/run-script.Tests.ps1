# Tests for steps/run-script.ps1, covering the ways a repository script can
# report failure. Run with: Invoke-Pester ./steps/run-script.Tests.ps1
#
# The point of these is that a step has to go red when the script it ran
# failed. Before these existed a failing test command left the job green.

BeforeAll {
    $script:Runner = Join-Path $PSScriptRoot 'run-script.ps1'
    $script:Fixtures = Join-Path ([IO.Path]::GetTempPath()) "run-script-tests-$(New-Guid)"
    New-Item -ItemType Directory -Force -Path $script:Fixtures | Out-Null

    # Each fixture takes RepoName so that run-script.ps1 has a parameter to
    # match, as it does with a real repository script.
    $Header = 'param([string]$RepoName)'

    Set-Content -Path "$script:Fixtures/passes.ps1" -Value @"
$Header
Write-Host "passes"
"@

    # Ends on a command that failed, which is how a test runner reports a
    # failing test.
    Set-Content -Path "$script:Fixtures/fails-at-the-end.ps1" -Value @"
$Header
Write-Host "Failed! - Failed: 9"
& (Get-Process -Id `$PID).Path -NoProfile -Command "exit 9"
"@

    # Fails part way through and then runs something that works, which is what
    # a script does when it tolerates a failure so that it can collect results.
    # The script reports success, so the step stays green. That is the script's
    # decision to make, not the runner's.
    Set-Content -Path "$script:Fixtures/fails-in-the-middle.ps1" -Value @"
$Header
& (Get-Process -Id `$PID).Path -NoProfile -Command "Write-Host 'Failed! - Failed: 3'; exit 3"
Write-Host "carrying on"
& (Get-Process -Id `$PID).Path -NoProfile -Command "exit 0"
"@

    # The same, but the script passes its own verdict on at the end, which is
    # what every language folder script in this repository does.
    Set-Content -Path "$script:Fixtures/fails-in-the-middle-and-says-so.ps1" -Value @"
$Header
& (Get-Process -Id `$PID).Path -NoProfile -Command "Write-Host 'Failed! - Failed: 3'; exit 3"
`$ok = `$LASTEXITCODE -eq 0
Write-Host "collecting results"
& (Get-Process -Id `$PID).Path -NoProfile -Command "exit 0"
exit `$ok ? 0 : 1
"@

    Set-Content -Path "$script:Fixtures/exits-one.ps1" -Value @"
$Header
Write-Host "about to exit 1"
exit 1
"@

    Set-Content -Path "$script:Fixtures/throws.ps1" -Value @"
$Header
throw "deliberate terminating error"
"@

    # Leaves a non zero code behind so the next test can show that the runner
    # does not read a stale code as the next script's result.
    Set-Content -Path "$script:Fixtures/leaves-a-stale-code.ps1" -Value @"
$Header
& (Get-Process -Id `$PID).Path -NoProfile -Command "exit 7"
"@
}

AfterAll {
    Remove-Item -Recurse -Force $script:Fixtures -ErrorAction SilentlyContinue
}

Describe 'run-script.ps1' {

    It 'stays quiet when the script passes' {
        { & $script:Runner "$script:Fixtures/passes.ps1" @{ RepoName = 'demo' } } |
            Should -Not -Throw
    }

    It 'fails when the script ends on a failing command' {
        { & $script:Runner "$script:Fixtures/fails-at-the-end.ps1" @{ RepoName = 'demo' } } |
            Should -Throw -ExpectedMessage "*fails-at-the-end.ps1' failed with exit code 9*"
    }

    It 'fails when the script exits non zero' {
        { & $script:Runner "$script:Fixtures/exits-one.ps1" @{ RepoName = 'demo' } } |
            Should -Throw -ExpectedMessage "*exits-one.ps1' failed with exit code 1*"
    }

    It 'fails when the script throws' {
        { & $script:Runner "$script:Fixtures/throws.ps1" @{ RepoName = 'demo' } } |
            Should -Throw -ExpectedMessage '*deliberate terminating error*'
    }

    It 'fails when a script that tolerated a failure passes its verdict on' {
        { & $script:Runner "$script:Fixtures/fails-in-the-middle-and-says-so.ps1" @{ RepoName = 'demo' } } |
            Should -Throw -ExpectedMessage "*fails-in-the-middle-and-says-so.ps1' failed with exit code 1*"
    }

    It 'leaves a script that swallowed its own failure alone' {
        # The runner reports what the script reported. A script that discards
        # its own exit code is a defect in that script, and this test records
        # that the runner does not paper over it.
        { & $script:Runner "$script:Fixtures/fails-in-the-middle.ps1" @{ RepoName = 'demo' } } |
            Should -Not -Throw
    }

    It 'does not read an earlier script exit code as this one' {
        # A real step leaves this behind when an earlier command failed.
        try {
            & $script:Runner "$script:Fixtures/leaves-a-stale-code.ps1" @{ RepoName = 'demo' }
        } catch {
            # Expected, and not what this test is about.
        }
        $global:LASTEXITCODE | Should -Be 7
        { & $script:Runner "$script:Fixtures/passes.ps1" @{ RepoName = 'demo' } } |
            Should -Not -Throw
    }

    It 'carries on and warns when the caller asks for the code to be ignored' {
        $out = & $script:Runner "$script:Fixtures/exits-one.ps1" @{ RepoName = 'demo' } -IgnoreExitCode
        ($out -join "`n") | Should -BeLike '*::warning title=Script failed*exit code 1*'
    }

    It 'reports the name of the script that failed' {
        $message = $null
        try {
            & $script:Runner "$script:Fixtures/exits-one.ps1" @{ RepoName = 'demo' }
        } catch {
            $message = $_.Exception.Message
        }
        $message | Should -BeLike '*exits-one.ps1*'
        $message | Should -BeLike '*exit code 1*'
    }
}
