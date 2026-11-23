param (
    [Parameter(Mandatory)][string]$FullFilePath,
    [Parameter(Mandatory)][string]$DataType,
    [Parameter(Mandatory)][string]$Product
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Data files come from the Distributor with the data license key, which the
# shared workflows set as _51DEGREES_LICENSE_KEY from
# LICENSE_KEY_V4TAC_IPIV4ENTERPRISE in the steps that download.
if ([string]::IsNullOrWhiteSpace($env:_51DEGREES_LICENSE_KEY)) {
    throw "'$FullFilePath' needs the data license key, and _51DEGREES_LICENSE_KEY is not set. The step that downloads sets it from the organization secret LICENSE_KEY_V4TAC_IPIV4ENTERPRISE, which the calling workflow passes with 'secrets: inherit'."
}

$Url = "https://distributor.51degrees.com/api/v2/download?LicenseKeys=$env:_51DEGREES_LICENSE_KEY&Type=$DataType&Download=True&Product=$Product"
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