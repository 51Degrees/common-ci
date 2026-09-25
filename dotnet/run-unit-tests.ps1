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

# Runs a single test-assembly invocation (supplied as a script block that leaves
# its native exit code in $LASTEXITCODE) with a narrow retry for the macOS
# bootstrap-time infra SIGKILL. That kill is a ~20% per-attempt flake: the test
# host dies within tens of milliseconds of launch, before any test runs, and the
# evidence collector has confirmed (5/5) it is NOT out-of-memory. Rather than
# always sleeping between attempts, we use the *duration* as the discriminator:
# a genuine bootstrap kill exits almost immediately, so we only retry a 137 that
# died faster than $FastExitThresholdMs. A 137 that arrives after real work ran
# is not this flake and is left to fail. On the final (or non-retryable) exit
# the evidence collector runs and the resolved exit code is returned. macOS only;
# every other OS runs the block exactly once.
function Invoke-AssemblyTest {
    param(
        [Parameter(Mandatory)][scriptblock]$TestScript,
        [Parameter(Mandatory)][string]$Assembly,
        [string]$ResultPath,
        [string]$Runner = "test",
        [int]$MaxSignalRetries = 2,
        [int]$FastExitThresholdMs = 200
    )

    $maxRetries = ($IsMacOS ? $MaxSignalRetries : 0)
    $attempt = 0
    do {
        $attempt++
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $TestScript
        $exitCode = $LASTEXITCODE
        $sw.Stop()
        $elapsedMs = $sw.ElapsedMilliseconds
        Write-Output "$Runner LastExitCode=$exitCode (elapsed ${elapsedMs}ms)"

        # Retry only a fast-exiting 137: that is the bootstrap SIGKILL signature.
        $retryable = ($exitCode -eq 137 -and $elapsedMs -lt $FastExitThresholdMs -and $attempt -le $maxRetries)
        if ($retryable) {
            Write-Output "Exit 137 after only ${elapsedMs}ms (SIGKILL at bootstrap) on attempt $attempt for $Assembly; retrying immediately (macOS infra flake gate)"
        }
    } while ($retryable)

    if ($exitCode -ne 0) {
        Write-Output "Setting ok=false due to $Runner exit code $exitCode for $Assembly"
        Write-SignalKillEvidence -ExitCode $exitCode -Assembly $Assembly -ResultPath $ResultPath
        $script:ok = $false
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
                Invoke-AssemblyTest -Assembly $NextFile.FullName -ResultPath $TestResultPath -Runner "dotnet test" -TestScript {
                    dotnet test $NextFile.FullName `
                        --no-build `
                        --configuration $Configuration `
                        @PlatformParams `
                        @testRunsettings `
                        --results-directory $TestResultPath `
                        --blame-crash --blame-hang-timeout $BlameHangTimeout -l "trx" $verbose
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
                Invoke-AssemblyTest -Assembly $NextFile.FullName -ResultPath $TestResultPath -Runner "vstest.console" -TestScript {
                    & vstest.console.exe $NextFile.FullName `
                        @PlatformParams `
                        /Logger:trx `
                        /ResultsDirectory:$TestResultPath
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
