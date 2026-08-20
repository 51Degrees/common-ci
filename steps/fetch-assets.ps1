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
    # The Available index returns version keys as YYYY/MM/DD, but the Download
    # endpoint expects YYYY-MM-DD - passing the key through verbatim builds a
    # slashed URL that 404s. Normalise to dashes. Also iterate newest-first and
    # fall back to older versions in case a given day's blob is genuinely
    # missing, and sort explicitly rather than trusting the API's key order.
    $versions = @($available.Keys | Sort-Object -Descending)
    if (-not $versions) {
        throw "No $Data versions listed by bulkdata in the last 30 days"
    }
    foreach ($version in $versions) {
        $datePath = $version -replace '/', '-'
        Write-Host "Downloading $Data from $version..."
        try {
            curl -fLo $Output "https://bulkdata.51degrees.com/api/v4/Download/Production/$Data/$License/$datePath"
            return
        } catch {
            Write-Warning "$Data $version is not downloadable ($_); trying an older version..."
        }
    }
    throw "No downloadable $Data version found in the last 30 days"
}

# Several assets are Git LFS objects (the Lite hash file alone is ~28MB) served
# by GitHub's media host. When the whole build matrix pulls the same object at
# once GitHub resets or stalls the connection, which failed the job outright
# because a bare curl has no retry. Note that --retry on its own is not enough:
# a reset (curl 35) is not in curl's default retry set, hence --retry-all-errors,
# and --speed-limit/--speed-time turns a stalled transfer into a retry rather
# than a hang that runs until the job is cancelled.
function Get-FromGitHub {
    param (
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Output
    )
    $retryArguments = @(
        '--retry', 5, '--retry-all-errors', '--retry-delay', 5,
        '--connect-timeout', 30, '--speed-limit', 1024, '--speed-time', 60
    )
    curl -fLo $Output @retryArguments $Url
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
            Get-FromGitHub -Url "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/51Degrees-LiteV4.1.hash" -Output $cache/$_
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
            & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url "https://51ddatafiles.blob.core.windows.net/enterpriseipi/51Degrees-IPIV4LiteIpiV41.ipi.gz"
            Move-Item -Path $_ -Destination $cache

        }
        "20000 Evidence Records.yml" {
            Get-FromGitHub -Url "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20Evidence%20Records.yml" -Output $cache/$_
        }
        "20000 User Agents.csv" {
            Get-FromGitHub -Url "https://media.githubusercontent.com/media/51Degrees/device-detection-data/main/20000%20User%20Agents.csv" -Output $cache/$_
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
            Get-FromGitHub -Url "https://raw.githubusercontent.com/51Degrees/ip-intelligence-data/main/evidence.yml" -Output $cache/$_
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
