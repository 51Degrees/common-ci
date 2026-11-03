# Tests for steps/package-update-required.ps1.
#
# The script decides from a checkout's tags and history, so each test builds a
# throwaway git repository tagged as a release, commits the change under test
# and runs the script against it. Exit code 0 means publish, 1 means do not.

BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'package-update-required.ps1'

    # A repository with a source file and a README, tagged 4.5.0, then one
    # commit for each group of files given, each file written with new text.
    function New-ReleasedRepo ([string[][]]$Commits, [switch]$NoTag) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        Set-Content -Path (Join-Path $path 'engine.c') -Value 'int x;'
        Set-Content -Path (Join-Path $path 'README.md') -Value 'Readme'
        git -C $path add --all
        git -C $path -c user.name=test -c user.email=test@example.com `
            commit --quiet -m 'Release'
        if (-not $NoTag) {
            git -C $path tag 4.5.0
        }
        foreach ($files in $Commits) {
            foreach ($file in $files) {
                $full = Join-Path $path $file
                New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
                Set-Content -Path $full -Value ([Guid]::NewGuid().ToString())
            }
            git -C $path add --all
            git -C $path -c user.name=test -c user.email=test@example.com `
                commit --quiet -m 'Change'
        }
        return $path
    }

    # Runs the check and returns its exit code and output together.
    function Invoke-Check ([string]$Repo, [string]$Version) {
        $output = & $script:Check -RepoName $Repo -Version $Version | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterEach {
    if ($script:Repo -and (Test-Path $script:Repo)) {
        Remove-Item -Recurse -Force $script:Repo
    }
    $script:Repo = $null
}

Describe 'package-update-required.ps1' {

    It 'does not publish a version that is already tagged' {
        $script:Repo = New-ReleasedRepo @()
        (Invoke-Check $script:Repo '4.5.0').ExitCode | Should -Be 1
    }

    It 'publishes when code changed since the last release' {
        $script:Repo = New-ReleasedRepo @(, @('engine.c'))
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 0
    }

    It 'does not publish when only Markdown files changed since the last release' {
        $script:Repo = New-ReleasedRepo @(@('README.md'), @('docs/guide.md'))
        $result = Invoke-Check $script:Repo '4.5.1'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Only documentation'
    }

    It 'treats a Markdown file of any case as documentation' {
        $script:Repo = New-ReleasedRepo @(, @('CHANGES.MD'))
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 1
    }

    It 'does not publish when only images under .github/images changed' {
        $script:Repo = New-ReleasedRepo @(, @('.github/images/logo.png'))
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 1
    }

    It 'publishes when documentation and code both changed' {
        $script:Repo = New-ReleasedRepo @(@('README.md'), @('engine.c'))
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 0
    }

    It 'publishes an image outside .github/images, which may be packaged' {
        $script:Repo = New-ReleasedRepo @(, @('assets/logo.png'))
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 0
    }

    It 'publishes from a repository with no release tag, as before' {
        $script:Repo = New-ReleasedRepo @(, @('README.md')) -NoTag
        (Invoke-Check $script:Repo '4.5.1').ExitCode | Should -Be 0
    }
}
