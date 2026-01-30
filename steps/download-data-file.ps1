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
curl -Lo $FullFilePath --connect-timeout 30 --retry 3 $Uri
