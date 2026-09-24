[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [string]$Configuration = "Release",
    [string]$Arch = "x64",
    [string]$BuildMethod="dotnet",
    [string]$BlameHangTimeout="5m",
    [string]$DirNameFormatForDotnet = "*bin*",
    [string]$DirNameFormatForNotDotnet = "*\bin\*",
    [string]$Filter,
    [string]$OutputFolder = "unit"
)

$SkipPlatformArgs = (($Arch -eq "Any CPU") -or ($Filter.Contains("dll")))
Write-Output "SkipPlatformArgs = $SkipPlatformArgs"

# Collects post-hoc evidence when a test host is killed by a signal (for
# example exit code 137 = 128 + SIGKILL). These kills land within tens of
# milliseconds of process launch - before the VSTest banner and before the
# Blame data collector attaches - so no crash dump is produced and a live
# memory poller cannot observe them. Instead we ask the OS, after the fact,
# whether the kernel killed the process for memory pressure (jetsam /
# memorystatus), and snapshot system memory. This turns an opaque "137" into
# a decidable signal: a genuine out-of-memory kill of our test host is a real
# defect to fix, whereas the absence of any memorystatus entry points at a
# non-memory SIGKILL (codesign, harness, hang cleanup). It never changes the
# pass/fail outcome and only runs on the failure path, so green runs pay
# nothing. macOS only, because that is where these kills are observed and
# where these tools exist.
function Write-SignalKillEvidence {
    param(
        [int]$ExitCode,
        [string]$Assembly,
        [string]$ResultPath
    )

    # 128 + N indicates termination by signal N. 137 = SIGKILL, 143 = SIGTERM.
    if (-not $IsMacOS -or $ExitCode -lt 129 -or $ExitCode -gt 159) {
        return
    }

    $signal = $ExitCode - 128
    try {
        Write-Output "::group::Signal-kill evidence (exit $ExitCode, signal $signal) for $Assembly"

        # 1. The decisive check: did the kernel's memorystatus/jetsam subsystem
        #    record a memory kill in the moments around the death? If our
        #    dotnet/testhost appears here, this is a real out-of-memory event.
        Write-Output "--- kernel memorystatus / jetsam (last 45s) ---"
        try {
            & log show --last 45s --style compact --predicate `
                'senderImagePath contains "kernel" and (eventMessage contains "memorystatus" or eventMessage contains "jetsam" or eventMessage contains "lowswap" or eventMessage contains "memory pressure")' `
                2>&1 | Select-Object -Last 40 | ForEach-Object { Write-Output $_ }
        } catch {
            Write-Output "log show unavailable: $($_.Exception.Message)"
        }

        # 2. Corroborating system memory pressure snapshot. Taken after the
        #    kill, so the victim's pages are already reclaimed - suggestive,
        #    not conclusive, and only meaningful alongside check 1.
        Write-Output "--- vm_stat ---"
        try { & vm_stat 2>&1 | ForEach-Object { Write-Output $_ } }
        catch { Write-Output "vm_stat unavailable: $($_.Exception.Message)" }

        Write-Output "--- swap usage ---"
        try { & sysctl vm.swapusage 2>&1 | ForEach-Object { Write-Output $_ } }
        catch { Write-Output "sysctl unavailable: $($_.Exception.Message)" }

        # 3. Records the known no-dump infrastructure gap: SIGKILL cannot be
        #    caught, so no crash reporter runs and Blame had not yet attached.
        #    Listed anyway because if anything ever does appear it ends the
        #    guesswork, and its emptiness documents the gap.
        Write-Output "--- crash artifacts (expected empty for SIGKILL) ---"
        try {
            $reports = Join-Path $HOME "Library/Logs/DiagnosticReports"
            $found = @()
            if (Test-Path $reports) {
                $found += Get-ChildItem -Path $reports -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) } |
                    ForEach-Object { $_.FullName }
            }
            if ($ResultPath -and (Test-Path $ResultPath)) {
                $found += Get-ChildItem -Path $ResultPath -Recurse -File -Include '*.dmp','Sequence_*.xml' -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName }
            }
            if ($found.Count -gt 0) { $found | ForEach-Object { Write-Output $_ } }
            else { Write-Output "(none - consistent with an uncatchable SIGKILL before Blame attached)" }
        } catch {
            Write-Output "artifact scan failed: $($_.Exception.Message)"
        }
    } catch {
        # The diagnostic must never itself affect the build outcome.
        Write-Output "Signal-kill evidence collection failed: $($_.Exception.Message)"
    } finally {
        Write-Output "::endgroup::"
    }
}

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$TestResultPath = [IO.Path]::Combine($RepoPath, "test-results", $OutputFolder, $Name)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    $script:ok = $true
    $verbose = $IsMacOS ? '--verbosity', 'd' : $null # macOS debugging

    $skipPattern = "*performance*"
    Write-Output "Testing '$Name'"
    Write-Output "BuildMethod: $BuildMethod"
    Write-Output "Initial ok value: $($script:ok)"
    Write-Output "Initial LASTEXITCODE: $LASTEXITCODE"

    # No LASTEXITCODE reset here. Assigning to it creates a script-scoped variable
    # that shadows the automatic one: the native calls below update the global,
    # every read here returns the shadow, and the exit code checks silently see 0
    # for every assembly. Nothing needs the reset - the only reads are immediately
    # after a native call below, where it is freshly set.
    if ($BuildMethod -eq "dotnet"){
        Write-Output "[dotnet] => Looking for '$Filter' in directories like '$DirNameFormatForDotnet'"

        $PlatformParams = $SkipPlatformArgs ? @() : @("-p:Platform=$Arch")
        $testRunsettings = [IO.Path]::Exists('test.runsettings') ? '--settings', 'test.runsettings' : $null

        foreach ($NextFile in (Get-ChildItem -Path $RepoPath -Recurse -File)) {
            $NextDirName = $NextFile.DirectoryName
            $NextFileName = $NextFile.Name
            Write-Debug "[$NextDirName]/[$NextFileName]"
            if ($NextDirName -notlike $DirNameFormatForDotnet) {
                Write-Debug "- $NextDirName not matched $DirNameFormatForDotnet"
            } elseif ($NextFileName -like $skipPattern) {
                Write-Debug "- $NextFileName matched $skipPattern"
            } elseif ($NextFileName -notmatch "$Filter") {
                Write-Debug "- $NextFileName not matched $Filter"
            } else {
                Write-Output "Testing Assembly: '$NextFile'"
                dotnet test $NextFile.FullName `
                    --no-build `
                    --configuration $Configuration `
                    @PlatformParams `
                    @testRunsettings `
                    --results-directory $TestResultPath `
                    --blame-crash --blame-hang-timeout $BlameHangTimeout -l "trx" $verbose
                Write-Output "dotnet test LastExitCode=$LASTEXITCODE"
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "Setting ok=false due to dotnet test exit code $LASTEXITCODE for $NextFile"
                    Write-SignalKillEvidence -ExitCode $LASTEXITCODE -Assembly $NextFile.FullName -ResultPath $TestResultPath
                    $script:ok = $false
                }
            }
        }
    } else {
        Write-Output "[$BuildMethod] ~> Looking for '$Filter' in directories like '$DirNameFormatForNotDotnet'"
        $PlatformParams = $SkipPlatformArgs ? @() : @("/Platform:$Arch")
        foreach ($NextFile in (Get-ChildItem -Path $RepoPath -Recurse -File)) {
            $NextDirName = $NextFile.DirectoryName
            $NextFileName = $NextFile.Name
            Write-Debug "[$NextDirName]/[$NextFileName]"
            if ($NextDirName -notlike $DirNameFormatForNotDotnet) {
                Write-Debug "- $NextDirName not matched $DirNameFormatForNotDotnet"
            } elseif ($NextFileName -like $skipPattern) {
                Write-Debug "- $NextFileName matched $skipPattern"
            } elseif ($NextFileName -notmatch "$Filter") {
                Write-Debug "- $NextFileName not matched $Filter"
            } else {
                Write-Output "Testing Assembly: '$NextFile'"
                & vstest.console.exe $NextFile.FullName `
                    @PlatformParams `
                    /Logger:trx `
                    /ResultsDirectory:$TestResultPath
                Write-Output "vstest.console LastExitCode=$LASTEXITCODE"
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "Setting ok=false due to vstest.console exit code $LASTEXITCODE for $NextFile"
                    Write-SignalKillEvidence -ExitCode $LASTEXITCODE -Assembly $NextFile.FullName -ResultPath $TestResultPath
                    $script:ok = $false
                }
            }
        }
    }

    Write-Output "Final test result: ok = $($script:ok)"
    if (!$script:ok) {
        Write-Error "Tests failed"
    }
} finally {
    Write-Output "Leaving '$RepoPath'"
    Pop-Location
}
