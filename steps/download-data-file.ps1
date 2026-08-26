param (
    [Parameter(Mandatory)][string]$FullFilePath,
    [string]$Url,
    [string]$LicenseKey,
    [string]$DataType,
    [string]$Product
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (!$Url -and (!$LicenseKey -or !$DataType -or !$Product)) {
    Write-Error "Either full Url or LicenseKey+DataType+Product must be provided"
}

$Url = $Url ? $Url : "https://distributor.51degrees.com/api/v2/download?LicenseKeys=$LicenseKey&Type=$DataType&Download=True&Product=$Product"
# Same rationale as the flags in fetch-assets.ps1, with two differences: these
# files are several GB, so there is no --max-time (any ceiling loose enough for
# a slow runner would never fire), and -C - resumes a retry from where the last
# attempt stopped instead of starting the transfer over. Curl only sends a Range
# header once there is partial data, so the first attempt is unaffected on a
# server that does not support ranges.
$curlFlags = @(
    '--retry', 5, '--retry-all-errors',
    '--connect-timeout', 30,
    '--speed-limit', 1024, '--speed-time', 60,
    '--continue-at', '-'
)

try {
    curl -fLo $FullFilePath @curlFlags $Url
} catch {
    # Never leave a partial file behind - callers treat the presence of the file
    # as proof that the download completed.
    if (Test-Path $FullFilePath) {
        Remove-Item -Force $FullFilePath
    }
    throw
}
