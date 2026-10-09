param (
    [Parameter(Mandatory)][string]$RepoName
)

# Logs evidence after a Maven test run has failed, so that a forked JVM that
# died ("The forked VM terminated without properly saying goodbye", exit code
# 1) can be diagnosed from the job log rather than guessed at.
#
# The JVM records why it died in hs_err_pid*.log: a native crash with the
# faulting frame, or "There is insufficient memory for the Java Runtime
# Environment to continue" when it could not commit native memory. Surefire
# records the fork's last words in *.dumpstream and *-jvmRun*.dump. All of these
# are written next to the tests and are lost with the runner, so the decisive
# lines are printed here instead. A snapshot of memory, page file and disk space
# follows. It is taken after the fork has died, so the fork's memory has already
# been released. hs_err holds the memory at the moment of death, and the
# snapshot adds the page file peak and the disk space, which hs_err does not.
#
# A JVM can also die without an hs_err file: something outside ends it, or a
# native library ends the process itself. For those cases the end of the
# redirected test output, the commit peak and the operating system's own
# record of processes dying or memory running out are printed too.
#
# Called by the Java test scripts only when Maven failed, so green runs pay
# nothing. It must never change the outcome, so every failure in here is
# reported and swallowed.

# The JVM writes hs_err here when it cannot write to its working directory.
$TempPath = [IO.Path]::GetTempPath()

# Lines of an hs_err file, after its "#" header, that say what the process
# and the machine looked like when the JVM died.
$HsErrKeyLinePattern =
    '^(Current thread|Command Line:|Memory:|OS:|Host:|' +
    'TotalPageFile|current process)'

function Write-Section {
    param([string]$Title)
    Write-Output "--- $Title ---"
}

# Prints the part of an hs_err file that says why the JVM died.
function Write-HsErrSummary {
    param([IO.FileInfo]$File)
    Write-Section $File.FullName
    $lines = @(Get-Content -Path $File.FullName -ErrorAction SilentlyContinue)
    # The header is the opening block of lines starting with "#". It holds the
    # error, the JRE version and the problematic frame.
    $lines |
        Select-Object -First 40 |
        Where-Object { $_.StartsWith("#") } |
        ForEach-Object { Write-Output $_ }
    $lines |
        Where-Object { $_ -match $HsErrKeyLinePattern } |
        Select-Object -First 20 |
        ForEach-Object { Write-Output $_ }
    # For a crash, the native frames show where in the native library it
    # happened. The section is absent for an out of memory error.
    $start = [Array]::FindIndex([string[]]$lines,
        [Predicate[string]]{ param($l) $l.StartsWith("Native frames:") })
    if ($start -ge 0) {
        $lines |
            Select-Object -Skip $start -First 20 |
            ForEach-Object { Write-Output $_ }
    }
}

# Prints every entry of a Surefire dump without its stack frames. On Windows
# every fork leaves a harmless "Cannot use PPID" entry first, so what Surefire
# said about the fork dying, if anything, is in a later entry. Cutting the file
# short would hide it. The frames are dropped because they are most of the
# file and say where Surefire was, not what happened to the fork.
function Write-SurefireDump {
    param([IO.FileInfo]$File)
    Write-Section $File.FullName
    Get-Content -Path $File.FullName -ErrorAction SilentlyContinue |
        Where-Object { $_ -notmatch '^\s+(at |\.\.\. \d+ more)' } |
        Where-Object { $_.Trim().Length -gt 0 } |
        Select-Object -First 60 |
        ForEach-Object { Write-Output $_ }
}

# Prints the end of the test output files written last. Where a project has
# Surefire redirect test output to files, what the fork wrote before it died
# is only there. That includes anything a native library printed to standard
# error before ending the process itself, which leaves no hs_err file.
function Write-TestOutputTails {
    param([string]$RepoPath)
    $outputFiles = @(Get-ChildItem -Path $RepoPath -File -Recurse -Force `
        -Filter "*-output.txt" -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -like "*surefire-reports*" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 3)
    if ($outputFiles.Count -eq 0) {
        Write-Output "(none - test output was not redirected to files)"
    }
    foreach ($file in $outputFiles) {
        Write-Section "$($file.FullName) (last 30 lines)"
        Get-Content -Path $file.FullName -Tail 30 `
            -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Output $_ }
    }
}

# Declares the Windows call that returns the system's memory counters.
function Add-PerformanceInfoType {
    Add-Type -Namespace FiftyOne -Name PerformanceInfo -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct Info {
    public uint Size;
    public UIntPtr CommitTotal;
    public UIntPtr CommitLimit;
    public UIntPtr CommitPeak;
    public UIntPtr PhysicalTotal;
    public UIntPtr PhysicalAvailable;
    public UIntPtr SystemCache;
    public UIntPtr KernelTotal;
    public UIntPtr KernelPaged;
    public UIntPtr KernelNonpaged;
    public UIntPtr PageSize;
    public uint HandleCount;
    public uint ProcessCount;
    public uint ThreadCount;
}
[DllImport("psapi.dll", SetLastError = true)]
public static extern bool GetPerformanceInfo(out Info info, uint size);
'@
}

# Windows keeps the highest commit charge since boot, which on a hosted runner
# is the highest of the job. If it reached the commit limit then an allocation
# was refused at some point, whatever the snapshot taken afterwards says.
function Write-WindowsCommitPeak {
    # Add-Type fails if the type is already defined in the session.
    if ($null -eq ('FiftyOne.PerformanceInfo' -as [type])) {
        Add-PerformanceInfoType
    }
    $info = New-Object FiftyOne.PerformanceInfo+Info
    $size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    if ([FiftyOne.PerformanceInfo]::GetPerformanceInfo([ref]$info, $size)) {
        # The counts are in pages.
        $pageMb = $info.PageSize.ToUInt64() / 1MB
        Write-Output ("Commit peak:     {0:N0} MB of a {1:N0} MB limit" -f
            ($info.CommitPeak.ToUInt64() * $pageMb),
            ($info.CommitLimit.ToUInt64() * $pageMb))
    }
    else {
        Write-Output "Commit peak:     not available"
    }
}

# Asks the operating system whether it recorded a process dying or memory
# running out. This is the only evidence when something outside the JVM ended
# it, as the JVM then writes nothing itself.
function Write-OperatingSystemEvents {
    if ($IsWindows) {
        # A hosted runner is booted for the job, so everything since boot
        # belongs to it.
        $since = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $providers = @(
            # A process crashed, or was reported to Windows Error Reporting.
            @{ LogName = 'Application'; ProviderName = 'Application Error' },
            @{ LogName = 'Application';
               ProviderName = 'Windows Error Reporting' },
            # Windows diagnosed the system as low on virtual memory.
            @{ LogName = 'System';
               ProviderName = 'Microsoft-Windows-Resource-Exhaustion-Detector' }
        )
        $events = @($providers | ForEach-Object {
            Get-WinEvent -FilterHashtable ($_ + @{ StartTime = $since }) `
                -MaxEvents 5 -ErrorAction SilentlyContinue
        })
        if ($events.Count -eq 0) {
            Write-Output "(none since boot at $since)"
        }
        foreach ($entry in ($events | Sort-Object -Property TimeCreated)) {
            $message = ($entry.Message -replace '\s+', ' ')
            if ($message.Length -gt 300) {
                $message = $message.Substring(0, 300) + "..."
            }
            Write-Output ("{0:HH:mm:ss} {1} ({2}): {3}" -f
                $entry.TimeCreated, $entry.ProviderName, $entry.Id, $message)
        }
    }
    elseif ($IsLinux) {
        # The kernel logs the process it kills when memory runs out.
        $killed = @(& sudo -n dmesg 2>$null |
            Where-Object { $_ -match 'out of memory|oom-kill|killed process' } |
            Select-Object -Last 10)
        if ($killed.Count -eq 0) {
            Write-Output "(no out of memory kills in the kernel log)"
        }
        $killed | ForEach-Object { Write-Output $_ }
    }
    else {
        Write-Output "(not collected on this operating system)"
    }
}

function Write-MemorySnapshot {
    if ($IsWindows) {
        # The commit limit is physical memory plus the page files. A process
        # that needs more than what is left of it cannot allocate, whatever
        # the free physical memory says. Win32 reports these in KB.
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Output ("Physical memory: {0:N0} MB total, {1:N0} MB free" -f
            ($os.TotalVisibleMemorySize / 1KB),
            ($os.FreePhysicalMemory / 1KB))
        Write-Output ("Commit limit:    {0:N0} MB total, {1:N0} MB free" -f
            ($os.TotalVirtualMemorySize / 1KB),
            ($os.FreeVirtualMemory / 1KB))
        # A peak usage equal to the allocated size means the page file was
        # full at some point in the job. Win32 reports these in MB.
        $pageFileFormat = "Page file '{0}': {1:N0} MB allocated, " +
            "{2:N0} MB used, {3:N0} MB peak"
        Get-CimInstance Win32_PageFileUsage | ForEach-Object {
            Write-Output ($pageFileFormat -f $_.Name, $_.AllocatedBaseSize,
                $_.CurrentUsage, $_.PeakUsage)
        }
        Write-WindowsCommitPeak
    }
    elseif ($IsLinux) {
        $fields = '^(MemTotal|MemAvailable|SwapTotal|SwapFree|' +
            'CommitLimit|Committed_AS):'
        Get-Content /proc/meminfo |
            Where-Object { $_ -match $fields } |
            ForEach-Object { Write-Output $_ }
    }
    elseif ($IsMacOS) {
        & sysctl hw.memsize vm.swapusage 2>&1 |
            ForEach-Object { Write-Output $_ }
        & vm_stat 2>&1 | ForEach-Object { Write-Output $_ }
    }
}

function Write-DiskSnapshot {
    Get-PSDrive -PSProvider FileSystem |
        Where-Object { $null -ne $_.Free } |
        ForEach-Object {
            Write-Output ("Drive '{0}' ({1}): {2:N1} GB used, {3:N1} GB free" -f
                $_.Name, $_.Root, ($_.Used / 1GB), ($_.Free / 1GB))
        }
    # A test that copies a large data file to the temp folder and then dies
    # leaves the copy behind, so the largest files there show what was
    # filling the disk.
    Write-Output "Largest files under '$TempPath':"
    Get-ChildItem -Path $TempPath -File -Recurse -Force `
        -ErrorAction SilentlyContinue |
        Sort-Object -Property Length -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            Write-Output ("  {0:N1} GB  {1}" -f ($_.Length / 1GB), $_.FullName)
        }
}

Write-Output "::group::JVM crash evidence for '$RepoName'"
try {
    $repoPath = Join-Path (Get-Location) $RepoName

    # Only hs_err files are looked for in the temp folder. It is shared with
    # every other process on the runner, and nothing else there is ours.
    $hsErrFiles = @(
        Get-ChildItem -Path $repoPath -File -Recurse -Force `
            -Filter "hs_err_pid*.log" -ErrorAction SilentlyContinue
        Get-ChildItem -Path $TempPath -File `
            -Filter "hs_err_pid*.log" -ErrorAction SilentlyContinue
    )
    $dumpFiles = @(Get-ChildItem -Path $repoPath -File -Recurse -Force `
        -Include "*.dumpstream", "*-jvmRun*.dump" -ErrorAction SilentlyContinue)

    if ($hsErrFiles.Count -eq 0) {
        # Without an hs_err file the JVM did not record its own death, which
        # is what happens when something outside it ends the process.
        Write-Output "No hs_err file: the JVM did not record why it stopped."
    }
    foreach ($file in $hsErrFiles) {
        Write-HsErrSummary -File $file
    }
    foreach ($file in $dumpFiles) {
        Write-SurefireDump -File $file
    }

    Write-Section "Test output"
    Write-TestOutputTails -RepoPath $repoPath

    Write-Section "Memory"
    Write-MemorySnapshot

    Write-Section "Disk"
    Write-DiskSnapshot

    Write-Section "Operating system events"
    Write-OperatingSystemEvents
}
catch {
    # The evidence must never itself affect the build outcome.
    Write-Output "JVM crash evidence collection failed: $($_.Exception.Message)"
}
finally {
    Write-Output "::endgroup::"
}

exit 0
