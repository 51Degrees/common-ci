# Tests for steps/install-gitversion.ps1 with stand-ins for dotnet and
# dotnet-gitversion, so nothing is installed. Run with:
# Invoke-Pester ./steps/install-gitversion.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot 'install-gitversion.ps1')

    # A runner that has $Present installed, or none when $null. A call to
    # dotnet tool update then puts $Gets in place, or leaves the runner as it
    # was and fails when $Gets is 'fail'.
    function Set-Runner([string]$Present, [string]$Gets, [int]$ExitCode = 0) {
        $script:Present = $Present
        $script:Gets = $Gets
        $script:ExitCode = $ExitCode
        $script:DotnetCalls = @()
    }

    function dotnet {
        $script:DotnetCalls += ($args -join ' ')
        $global:LASTEXITCODE = $script:ExitCode
        if ($script:ExitCode -eq 0) { $script:Present = $script:Gets }
    }

    function dotnet-gitversion {
        if ($null -eq $script:Present) {
            throw 'The term dotnet-gitversion is not recognized.'
        }
        if ($args -contains '/version') { return $script:Present }
    }
}

Describe 'Get-InstalledGitVersion' {
    It 'is $null when GitVersion is not installed' {
        Set-Runner $null $null
        Get-InstalledGitVersion | Should -BeNullOrEmpty
    }

    It 'reads the version before any build metadata' {
        Set-Runner '6.8.2+Branch.main.Sha.abc' $null
        Get-InstalledGitVersion | Should -Be '6.8.2'
    }

    It 'does not take a pre-release for the release' {
        Set-Runner '6.8.2-beta.1' $null
        Get-InstalledGitVersion | Should -BeNullOrEmpty
    }
}

Describe 'Install-GitVersion' {
    It 'leaves the right version alone' {
        Set-Runner '6.8.2' '6.8.2'
        Install-GitVersion -Version '6.8.2'
        $script:DotnetCalls | Should -BeNullOrEmpty
    }

    It 'installs when GitVersion is missing' {
        Set-Runner $null '6.8.2'
        Install-GitVersion -Version '6.8.2'
        $script:DotnetCalls | Should -Be 'tool update --global GitVersion.Tool --version 6.8.2'
    }

    It 'changes a different version to the one asked for' {
        Set-Runner '6.1.0' '6.8.2'
        Install-GitVersion -Version '6.8.2'
        $script:DotnetCalls | Should -Be 'tool update --global GitVersion.Tool --version 6.8.2'
    }

    It 'fails when the version is still wrong afterward' {
        Set-Runner '6.1.0' '6.1.0'
        { Install-GitVersion -Version '6.8.2' } | Should -Throw '*6.1.0*6.8.2*'
    }

    It 'fails when dotnet fails' {
        Set-Runner '6.1.0' '6.8.2' 1
        { Install-GitVersion -Version '6.8.2' } | Should -Throw
    }

    It 'refuses a version that is not exact' {
        Set-Runner '6.8.2' '6.8.2'
        { Install-GitVersion -Version '6.1' } | Should -Throw '*exact*'
    }
}
