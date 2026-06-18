param(
    # The directory the rust workspace is checked out to. CI checks the repo out
    # into a subdirectory named after the repository, matching the other
    # languages; a local run can pass "." for the current directory.
    [string]$RepoName = ".",
    # Where the results files are written, relative to the repo directory. This is
    # the path the nightly workflow uploads and the compare-performance step reads.
    [string]$OutputDir = "test-results/performance-summary"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Runs the 51Degrees Rust on-premise performance examples in release and writes
# their throughput figures into results_<Name>.json files, in the same
# `{ HigherIsBetter = @{ metric = value } }` shape the shared
# steps/compare-performance.ps1 consumes. The Rust on-premise engines call the
# device-detection-cxx and ip-intelligence-cxx libraries through FFI, so the
# figures track the native C/C++ performance.

Push-Location $RepoName
try {
    $summaryDir = Join-Path (Get-Location) $OutputDir
    New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null

    # The example crates live in their own workspace under examples/ and depend
    # on the published crates from crates.io by default. The nightly must
    # benchmark this checkout's engine code, not the released packages, so the
    # cargo commands run from examples/ with `--config source.toml`, the patch
    # file that points every fiftyone-* dependency at its local path.
    $examplesDir = Join-Path (Get-Location) "examples"

    # Run one performance example and parse the throughput it prints. The
    # examples take the highest throughput figure they report (the multi-threaded
    # pass), which is the headline number for the product.
    function Get-Throughput {
        param(
            [Parameter(Mandatory)][string]$Package,
            [Parameter(Mandatory)][string]$Bin,
            [Parameter(Mandatory)][string]$Pattern
        )
        Write-Host "Running performance example '$Bin'..."
        Push-Location $examplesDir
        try {
            $output = cargo run --release --config source.toml -p $Package --bin $Bin 2>&1 | Out-String
        } finally {
            Pop-Location
        }
        Write-Host $output
        $found = [regex]::Matches($output, $Pattern)
        if ($found.Count -eq 0) {
            Write-Error "Could not parse a throughput figure from '$Bin' output"
        }
        # Take the last match so the multi-threaded figure wins where an example
        # prints both a single- and a multi-threaded result.
        return [double]$found[$found.Count - 1].Groups[1].Value
    }

    # Device Detection on-premise (Hash): detections per second.
    $ddDetectionsPerSecond = Get-Throughput `
        -Package "device-detection-examples" `
        -Bin "dd-onprem-performance" `
        -Pattern "Detections per second\s*:\s*(\d+)"
    @{ HigherIsBetter = @{ DetectionsPerSecond = $ddDetectionsPerSecond } } |
        ConvertTo-Json -Depth 5 |
        Out-File (Join-Path $summaryDir "results_DeviceDetection-OnPremise.json") -Encoding utf8

    # IP Intelligence on-premise (IP graph): lookups per second.
    $ipiLookupsPerSecond = Get-Throughput `
        -Package "ip-intelligence-examples" `
        -Bin "ipi-onprem-performance" `
        -Pattern "Throughput:\s*(\d+)\s*lookups/sec"
    @{ HigherIsBetter = @{ LookupsPerSecond = $ipiLookupsPerSecond } } |
        ConvertTo-Json -Depth 5 |
        Out-File (Join-Path $summaryDir "results_IpIntelligence-OnPremise.json") -Encoding utf8

    Write-Host "Wrote performance results to '$summaryDir':"
    Get-ChildItem $summaryDir -Filter "results_*.json" | ForEach-Object { Write-Host " - $($_.Name)" }
} finally {
    Pop-Location
}
