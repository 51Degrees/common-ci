# Alternative to https://github.com/51Degrees/ApacheBench/ (not fully, but to
# what was actually used by projects) that doesn't depend on Apache libraries
# which recently stopped being available for Windows on the website and caused
# CI failures across all projects that used ApacheBench in their tests. This
# script only depends on the curl binary.
param (
    [Parameter(Mandatory)][string]$HostPort,
    [Parameter(Mandatory)][string]$UaFile,
    [string]$Endpoint = '/',
    [string]$CalibrateEndpoint = $Endpoint
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Waiting for the server..."
$devNull = $IsWindows ? 'nul' : '/dev/null'
# with the default backoff algorithm 5 retries should take approximately 30s
curl -sS -o $devNull --retry 5 --retry-connrefused "$HostPort$CalibrateEndpoint"

$uas = Get-Content $UaFile
$xStockDevice = "Device-Stock-UA", "X-Device-User-Agent", "X-OperaMini-Phone-UA"

function Measure-HttpPerf {
    param ([string]$Endpoint)
    $random = New-Object System.Random -ArgumentList 42 # Get-Random is super slow, use seeded C# Random
    Write-Host "Benchmarking $HostPort$Endpoint with $($uas.Count) requests..."
    $results = 1..$uas.Count | ForEach-Object {
        "next"
        "url = $HostPort$Endpoint"
        "header = `"User-Agent: $($uas[$random.Next($uas.Count)])`""
        "header = `"$($xStockDevice[$random.Next($xStockDevice.Count)]): $($uas[$random.Next($uas.Count)])`""
        "output = $devNull"
        "write-out = `"%{exitcode} %{http_code} %{time_total}\n`""
    } | curl -sS --config -
    [int]$errors = 0
    [int]$httpErrors = 0
    [double]$totalSeconds = 0.0
    foreach ($result in $results) {
        [int]$exitCode, [int]$httpCode, [double]$time = -split $result
        if ($exitCode -gt 0) { ++$errors }
        if ($httpCode -ge 300) { ++$httpErrors }
        $totalSeconds += $time
    }
    $errors
    $httpErrors
    $totalSeconds
}
$calibrateErrors, $calibrateHttpErrors, $calibrateTotalSeconds = Measure-HttpPerf -Endpoint $CalibrateEndpoint
$errors, $httpErrors, $totalSeconds = Measure-HttpPerf -Endpoint $Endpoint

Write-Host "Calibrate errors = $calibrateErrors; HTTP errors = $calibrateHttpErrors; total seconds = $calibrateTotalSeconds"
Write-Host "Errors = $errors; HTTP errors = $httpErrors; total seconds = $totalSeconds"

@{
    'overhead_ms' = ($totalSeconds - $calibrateTotalSeconds) / $uas.Count * 1000
    'non_200_responses_process' = $httpErrors
    'failed_process' = $errors
    'non_200_responses_calibrate' = $calibrateHttpErrors
    'failed_calibrate' = $calibrateErrors
    'request_s_process' = $totalSeconds
    'request_s_calibrate' = $calibrateTotalSeconds
}
