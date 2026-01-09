param (
    [Parameter(Mandatory)][string[]]$Assets,
    [string]$DeviceDetection,
    [string]$DeviceDetectionUrl,
    [string]$IpIntelligenceUrl,
    [string]$CsvUrl,
    [switch]$FullCsv
)
$ErrorActionPreference = "Stop"

$cache = New-Item -ItemType Directory -Path assets -Force

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
            Invoke-WebRequest -Uri "https://github.com/51Degrees/device-detection-data/raw/main/51Degrees-LiteV4.1.hash" -OutFile $cache/$_
        }
        "51Degrees-EnterpriseIpiV41.ipi" {
            # Only uses URL because IPI doesn't support specifying DataType and Product for now
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url $IpIntelligenceUrl
            Move-Item -Path $_ -Destination $cache
        }
        "51Degrees-EnterpriseIpiV41-AllProperties.ipi" {
            # Only uses URL because IPI doesn't support specifying DataType and Product for now
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url $IpIntelligenceUrl
            Move-Item -Path $_ -Destination $cache
        }
        "51Degrees-LiteIpiV41.ipi" {
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url "https://51ddatafiles.blob.core.windows.net/enterpriseipi/51Degrees-LiteIpiV41.ipi.gz"
            Move-Item -Path $_ -Destination $cache

        }
        "20000 Evidence Records.yml" {
            Invoke-WebRequest -Uri "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20Evidence%20Records.yml" -OutFile $cache/$_
        }
        "20000 User Agents.csv" {
            Invoke-WebRequest -Uri "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20User%20Agents.csv" -OutFile $cache/$_
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
        default { Write-Error "Unknown asset: $_" }
    }
}
