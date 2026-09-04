<#
.SYNOPSIS
Runs the 51Degrees Rust on-premise performance examples and publishes their
results.

.DESCRIPTION
Each example writes its own results JSON in the shared schema (see
steps/publish-performance-results.ps1), so this adapter only runs the examples
and hands their files over. It does not parse the examples' console output.

The Rust on-premise engines call the device-detection-cxx and
ip-intelligence-cxx libraries through FFI, so the figures track the native
C/C++ performance.
#>
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

$publishStep = Join-Path $PSScriptRoot "../steps/publish-performance-results.ps1"

# The example crates live in their own workspace under examples/ and depend on
# the published crates from crates.io by default. The nightly must benchmark
# this checkout's engine code, not the released packages, so the cargo commands
# run from examples/ with `--config source.toml`, the patch file that points
# every fiftyone-* dependency at its local path.
$examplesDir = Join-Path (Resolve-Path $RepoName) "examples"

# Run one performance example, asking it to write its results JSON, and publish
# that file under the configuration name the graph is keyed on.
function Invoke-PerformanceExample {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Bin,
        [Parameter(Mandatory)][string]$Name
    )
    # An absolute path, because the example runs with examples/ as its working
    # directory but the results are published under the repository directory.
    $resultsFile = Join-Path ([System.IO.Path]::GetTempPath()) "results_$Name.json"
    Remove-Item -Path $resultsFile -Force -ErrorAction SilentlyContinue

    Write-Host "Running performance example '$Bin'..."
    Push-Location $examplesDir
    try {
        cargo run --release --config source.toml -p $Package --bin $Bin -- --json-output $resultsFile
    } finally {
        Pop-Location
    }

    & $publishStep -SourceFile $resultsFile -Name $Name -RepoName $RepoName -SummaryDir $OutputDir
}

# Device Detection on-premise (Hash): detections per second.
Invoke-PerformanceExample -Package "device-detection-examples" -Bin "dd-onprem-performance" -Name "DeviceDetection-OnPremise"

# IP Intelligence on-premise (IP graph): lookups per second.
Invoke-PerformanceExample -Package "ip-intelligence-examples" -Bin "ipi-onprem-performance" -Name "IpIntelligence-OnPremise"
