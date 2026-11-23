# Checks that a repository's ci/fetch-assets.ps1 runs with the data license,
# and that nothing after it does. Run with:
# Invoke-Pester ./steps/run-fetch-assets.Tests.ps1

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'run-fetch-assets.ps1'
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Describe 'run-fetch-assets.ps1' {

    BeforeEach {
        $script:Saved = [Environment]::GetEnvironmentVariable('_51DEGREES_LICENSE_KEY')
        Remove-Item -Path Env:_51DEGREES_LICENSE_KEY -ErrorAction SilentlyContinue

        # A stand-in repository whose script records the license it sees.
        $script:Seen = Join-Path $TestDrive 'seen.txt'
        $ci = Join-Path $TestDrive 'repo/ci'
        New-Item -ItemType Directory -Path $ci -Force | Out-Null
        Set-Content -Path (Join-Path $ci 'fetch-assets.ps1') -Value @"
param([string]`$RepoName)
Set-Content -Path '$script:Seen' -Value "[`$env:_51DEGREES_LICENSE_KEY]"
"@
        Push-Location $TestDrive
    }

    AfterEach {
        Pop-Location
        if ($null -eq $script:Saved) {
            Remove-Item -Path Env:_51DEGREES_LICENSE_KEY -ErrorAction SilentlyContinue
        } else {
            $env:_51DEGREES_LICENSE_KEY = $script:Saved
        }
    }

    It 'runs the script with the license as _51DEGREES_LICENSE_KEY' {
        & $script:Step -RepoName repo -Options @{ RepoName = 'repo' } -License 'value-data-license-4d1e'
        Get-Content -Path $script:Seen | Should -Be '[value-data-license-4d1e]'
    }

    It 'takes the license away once the script has run' {
        & $script:Step -RepoName repo -License 'value-data-license-4d1e'
        Test-Path -Path Env:_51DEGREES_LICENSE_KEY | Should -BeFalse
    }

    It 'puts back a value that was there before' {
        $env:_51DEGREES_LICENSE_KEY = 'value-before-7f20'
        & $script:Step -RepoName repo -License 'value-data-license-4d1e'
        Get-Content -Path $script:Seen | Should -Be '[value-data-license-4d1e]'
        $env:_51DEGREES_LICENSE_KEY | Should -Be 'value-before-7f20'
    }

    It 'runs the script without the variable when there is no license' {
        $env:_51DEGREES_LICENSE_KEY = 'value-before-7f20'
        & $script:Step -RepoName repo -License ''
        Get-Content -Path $script:Seen | Should -Be '[]'
        $env:_51DEGREES_LICENSE_KEY | Should -Be 'value-before-7f20'
    }

    It 'takes the license away when the script fails' {
        Set-Content -Path (Join-Path $TestDrive 'repo/ci/fetch-assets.ps1') -Value 'throw "failed"'
        { & $script:Step -RepoName repo -License 'value-data-license-4d1e' } | Should -Throw
        Test-Path -Path Env:_51DEGREES_LICENSE_KEY | Should -BeFalse
    }
}

Describe 'The scripts that fetch a repository''s assets' {

    # Each takes the data license out of the environment before it runs
    # anything, and hands it to the fetch alone.
    It '<_> takes the data license out of the environment first and fetches through run-fetch-assets.ps1' -ForEach @(
        'nightly-pull-request.build-and-test.ps1'
        'nightly-publish.test.ps1'
    ) {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:Root $_)
        $removed = $text.IndexOf('Remove-Item -Path Env:LICENSE_KEY_DATA_FILES')
        $removed | Should -BeGreaterThan 0
        $removed | Should -BeLessThan $text.IndexOf('./steps/')
        $text | Should -Match 'run-fetch-assets\.ps1 -RepoName \$RepoName -Options \$Options -License \$DataLicense'
        $text | Should -Not -Match 'run-script\.ps1 \./\$RepoName/ci/fetch-assets\.ps1'
    }
}
