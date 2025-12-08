param (
    [Parameter(Mandatory)][string]$HostPort,
    [Parameter(Mandatory)][string]$UaFile,
    [string]$Endpoint = '/',
    [string]$CalibrateEndpoint = $Endpoint
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Random = New-Object System.Random # Get-Random is super slow
$devNull = $IsWindows ? 'nul' : '/dev/null'

Write-Host "Waiting for the server..."
# with the default backoff algorithm 5 retries should take approximately 30s
curl -sS -o $devNull --retry 5 --retry-connrefused "$HostPort$Endpoint"

$uas = Get-Content $UaFile
$xStockDevice = "Device-Stock-UA", "X-Device-User-Agent", "X-OperaMini-Phone-UA"

Write-Host "Generating $($uas.Count) requests..."
1..$uas.Count | ForEach-Object {
    "next"
    "url = $HostPort$Endpoint"
    "header = `"User-Agent: $($uas[$Random.Next($uas.Count)])`""
    "header = `"$($xStockDevice[$Random.Next($xStockDevice.Count)]): $($uas[$Random.Next($uas.Count)])`""
    "output = $devNull"
    "write-out = `"%{exitcode} %{http_code} %{time_total}\n`""
} > requests.txt

function Measure-HttpPerf {
    param ([string]$Endpoint)
    Write-Host "Benchmarking $HostPort$Endpoint"
    $results = curl -sS --config requests.txt
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

Write-Host "Calibrate errors = $calibrateTotalSeconds; HTTP errors = $calibrateHttpErrors; total seconds = $calibrateTotalSeconds"
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
