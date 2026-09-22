# Tests for dotnet/run-update-dependencies.ps1, covering the arguments it
# hands to "dotnet list package".
# Run with: Invoke-Pester ./dotnet/run-update-dependencies.Tests.ps1
#
# The point of these is that the script has to speak a dialect of the dotnet
# CLI that the installed SDK understands. When it passed --no-restore, an SDK
# older than .NET 10 answered "Unrecognized command or argument" and printed
# its help. The script read that help where it expected JSON, recorded a
# failure for every project, and finished having found no update at all
# whilst exiting non zero. These tests fail against that version on any SDK
# that predates .NET 10.
#
# The listing reaches nuget.org, as the nightly it belongs to always has.

BeforeAll {
    $script:Updater = Join-Path $PSScriptRoot 'run-update-dependencies.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path

    # The script takes a repository name and looks for that folder under the
    # working directory, so the fixture has to be shaped the same way.
    $script:Workspace = Join-Path ([IO.Path]::GetTempPath()) "update-deps-tests-$(New-Guid)"
    $script:RepoName = 'fixture-repo'
    $script:RepoPath = Join-Path $script:Workspace $script:RepoName
    New-Item -ItemType Directory -Force -Path $script:RepoPath | Out-Null

    # A package with a long release history, pinned behind its newest patch,
    # so that --outdated has something to report.
    Set-Content -Path (Join-Path $script:RepoPath 'Fixture.csproj') -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
  </ItemGroup>
</Project>
'@

    # An SDK sits on the runner alongside any that setup-dotnet adds, and the
    # newest one wins unless a global.json says otherwise. The bug only shows
    # on an SDK older than .NET 10, so the workflow names the band to pin and
    # this resolves it to an exact installed version, which is the only form
    # global.json accepts. Unset, the default SDK is used and the test still
    # guards the arguments.
    $script:SdkBand = $env:COMMON_CI_TEST_SDK
    if ([string]::IsNullOrWhiteSpace($script:SdkBand) -eq $false) {
        # A preview SDK carries a suffix that will not cast to a version,
        # so those are dropped rather than left to throw mid sort.
        $InstalledSdks = (dotnet --list-sdks) |
            ForEach-Object { ($_ -split ' ')[0] } |
            Where-Object { $_.StartsWith("$script:SdkBand.") -and ($_ -as [version]) }
        if (@($InstalledSdks).Count -eq 0) {
            throw "No release .NET SDK matching '$script:SdkBand' is installed"
        }
        # Highest matching version, compared as a version rather than as text
        # so that 8.0.100 does not sort above 8.0.424.
        $ExactSdk = @($InstalledSdks | Sort-Object { [version]$_ })[-1]
        Set-Content -Path (Join-Path $script:RepoPath 'global.json') -Value @"
{ "sdk": { "version": "$ExactSdk", "rollForward": "disable" } }
"@
    }

    # Run the script once, the way a CI step does: in a separate process, so
    # that its exit code is the one asserted on and its "exit" cannot end
    # Pester. The child is told where to start explicitly rather than
    # inheriting it, because the script resolves the repository folder
    # against its own working directory. Running it a second time would find
    # the fixture already updated, so the assertions below share one result.
    $RunCommand =
        "Set-Location -LiteralPath '$script:Workspace'; " +
        "& '$script:Updater' -RepoName '$script:RepoName'; exit `$LASTEXITCODE"
    $RunOutput = & $script:Pwsh -NoProfile -Command $RunCommand 2>&1
    $script:RunExitCode = $LASTEXITCODE
    $script:RunOutput = ($RunOutput | Out-String)
}

AfterAll {
    Remove-Item -Recurse -Force $script:Workspace -ErrorAction SilentlyContinue
}

Describe 'run-update-dependencies.ps1' {

    It 'passes only arguments the installed SDK accepts' {
        # The exact symptom of the bug: the SDK rejected an argument and
        # printed its help, which the script then tried to read as JSON.
        $script:RunOutput | Should -Not -BeLike '*Unrecognized command or argument*'
    }

    It 'reads the package listing as JSON' {
        # The script warns with this text whenever a listing did not come
        # back as JSON, which is what happened for every project.
        $script:RunOutput | Should -Not -BeLike '*NOT A VALID JSON*'
    }

    It 'reports no failure to list outdated packages' {
        # Every rejected listing was collected and reported under this
        # heading, so its absence is what a working listing looks like.
        $script:RunOutput | Should -Not -BeLike '*Failures to list outdated packages*'
    }

    It 'succeeds over a project it can list' {
        # Every listing failing left the whole run exiting non zero, which is
        # what turned the nightly red once the step reported exit codes.
        $script:RunExitCode | Should -Be 0
    }
}
