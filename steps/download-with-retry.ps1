param (
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$Output,
    # Hard ceiling for a single attempt, in seconds. Only pass this for
    # downloads of a known, bounded size - the data files are several GB and
    # any limit generous enough for them on a slow runner would be too coarse
    # to catch anything, so those rely on the transfer speed floor instead.
    [int]$MaxTime,
    # Resume a retry from where the previous attempt stopped instead of
    # starting again. Worth it for the multi-GB data files, where a runner
    # pulling at ~1MB/s takes the best part of an hour and restarting from zero
    # can outlast the job. Curl only sends a Range header once there is partial
    # data to resume from, so the first attempt is unaffected on a server that
    # does not support ranges.
    [switch]$Resume
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$curlArguments = @(
    # --retry alone is not enough: a connection reset (curl 35) and a receive
    # timeout (curl 56) are not in curl's default retry set, which is exactly
    # what these downloads keep failing on. Note also that no --retry-delay is given on purpose - curl's
    # default exponential backoff staggers matrix jobs that were all reset at
    # the same moment, whereas a fixed delay would retry them in lockstep.
    '--retry', 5, '--retry-all-errors',
    '--connect-timeout', 30,
    # Abort an attempt that has trickled below 1KB/s for a minute so that it is
    # retried, rather than hanging until the job times out or is cancelled.
    '--speed-limit', 1024, '--speed-time', 60
)
if ($MaxTime) {
    $curlArguments += @('--max-time', $MaxTime)
}
if ($Resume) {
    $curlArguments += @('--continue-at', '-')
}

try {
    curl -fLo $Output @curlArguments $Url
} catch {
    # Never leave a truncated file behind. Callers treat the presence of a file
    # as proof that the asset is complete, so a partial download would be taken
    # for a valid cached asset on the next run. Done here rather than with
    # curl's --remove-on-error because that option needs curl 7.83, and the
    # ubuntu-22.04 runner image is still on 7.81.
    if (Test-Path $Output) {
        Remove-Item -Force $Output
    }
    throw
}
