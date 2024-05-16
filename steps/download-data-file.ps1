param (
    [Parameter(Mandatory=$true)]
    [string]$LicenseKey,
    [Parameter(Mandatory=$true)]
    [string]$DataType,
    [Parameter(Mandatory=$true)]
    [string]$Product,
    [Parameter(Mandatory=$true)]
    [string]$FullFilePath,
    [string]$Url = $Null
)

$Url ??= "https://distributor.51degrees.com/api/v2/download?LicenseKeys=$LicenseKey&Type=$DataType&Download=True&Product=$Product"
$InformationPreference = 'Continue'
Write-Information ($Url -replace '^https?://', '')
Invoke-WebRequest -Verbose -Uri $Url -OutFile $FullFilePath -MaximumRetryCount 3 -RetryIntervalSec 3 -ConnectionTimeoutSeconds 30 -OperationTimeoutSeconds 30
