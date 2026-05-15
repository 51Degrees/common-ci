param (
    [Parameter(Mandatory)][string[]]$Assets,
    [string]$DeviceDetection,
    [string]$DeviceDetectionUrl,
    [string]$IpIntelligence,
    [string]$IpIntelligenceUrl,
    [string]$CsvUrl,
    [switch]$FullCsv
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$cache = New-Item -ItemType Directory -Path assets -Force

function Get-FromBulkData {
    param (
        [Parameter(Mandatory)][string]$License,
        [Parameter(Mandatory)][string]$Data,
        [Parameter(Mandatory)][string]$Output
    )
    $monthAgo = [DateTime]::Now.AddDays(-30).ToString('yyyy-MM-dd')
    $tomorrow = [DateTime]::Now.AddDays(1).ToString('yyyy-MM-dd')
    Write-Host "Retrieving the latest $Data version..."
    $available = Invoke-WebRequest "https://bulkdata.51degrees.com/api/v4/Available/Production/$Data/$License/$monthAgo/$tomorrow" | ConvertFrom-Json -AsHashtable
    $latest = $available.Keys | Select-Object -Last 1
    Write-Host "Downloading $Data from $latest..."
    curl -fLo $Output "https://bulkdata.51degrees.com/api/v4/Download/Production/$Data/$License/$latest"
}

foreach ($asset in $Assets) {
    if (Test-Path $cache/$asset) {
        Write-Host "Asset '$asset' already present in cache, skipping download"
        continue
    }
    Write-Host "Fetching '$asset'"
    switch -Exact -CaseSensitive ($asset) {
        "TAC-HashV41.hash" {
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -LicenseKey $DeviceDetection -Url $DeviceDetectionUrl
            Move-Item -Path $_ -Destination $cache
        }
        "51Degrees-LiteV4.1.hash" {
            curl -fLo $cache/$_ "https://github.com/51Degrees/device-detection-data/raw/main/51Degrees-LiteV4.1.hash"
        }
        "51Degrees-EnterpriseIpiV41.ipi" {
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -LicenseKey $IpIntelligence -DataType IPIV41 -Product IPIV4Enterprise -Url $IpIntelligenceUrl
            Move-Item -Path $_ -Destination $cache
        }
        "51Degrees-EnterpriseIpiV41-AllProperties.ipi" {
            # Only uses URL
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url $IpIntelligenceUrl
            Move-Item -Path $_ -Destination $cache
        }
        "51Degrees-LiteIpiV41.ipi" {
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url "https://51ddatafiles.blob.core.windows.net/enterpriseipi/51Degrees-LiteIpiV41.ipi.gz"
            Move-Item -Path $_ -Destination $cache

        }
        "20000 Evidence Records.yml" {
            curl -fLo $cache/$_ "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20Evidence%20Records.yml"
        }
        "20000 User Agents.csv" {
            curl -fLo $cache/$_ "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20User%20Agents.csv"
        }
        "51Degrees.csv" {
            & $PSScriptRoot/download-data-file.ps1 -LicenseKey:$DeviceDetection -DataType 'CSV' -Product 'V4TAC' -Url:$CsvUrl -FullFilePath "$_.zip"
            Expand-Archive -DestinationPath . "$_.zip"
            if ($FullCsv) {
                Move-Item -Path '51Degrees-Tac-All.csv' -Destination $cache/$_
            } else {
                Get-Content -TotalCount 1 '51Degrees-Tac-All.csv' > $cache/$_ # Most repos only need the header
            }
            Remove-Item -Force "$_.zip", '51Degrees-Tac-All.csv'
        }
        "51Degrees-Tac.zip" {  # same as the CSV above, without extracting
            & $PSScriptRoot/download-data-file.ps1 -LicenseKey:$DeviceDetection -DataType 'CSV' -Product 'V4TAC' -Url:$CsvUrl -FullFilePath "$cache/$_"
        }
        "ip-intelligence-evidence.yml" {
            curl -fLo $cache/$_ "https://raw.githubusercontent.com/51Degrees/ip-intelligence-data/main/evidence.yml"
        }
        "chargify.json" {
            Get-FromBulkData -License:$DeviceDetection -Data 'chargify' -Output $cache/$_
        }
        "entitlement.json" {
            Get-FromBulkData -License:$DeviceDetection -Data 'entitlement' -Output $cache/$_
        }
        default { Write-Error "Unknown asset: $_" }
    }
}
