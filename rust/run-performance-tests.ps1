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

# The example crates depend on the published crates from crates.io by default,
# so cargo runs from examples/ with `--config source.toml`, the patch file that
# points every fiftyone-* dependency at its local path.
$examplesDir = Join-Path (Resolve-Path $RepoName) "examples"

function Invoke-PerformanceExample {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Bin,
        [Parameter(Mandatory)][string]$Name
    )
    # Absolute, because the example runs from examples/ but publishes under the repo.
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
