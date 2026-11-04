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

# --retry alone is not enough: a connection reset (curl 35) and a receive
# timeout (curl 56) are not in curl's default retry set, and those are what
# these downloads keep failing on. No --retry-delay on purpose - curl's default
# exponential backoff staggers matrix jobs that were all reset at the same
# moment, whereas a fixed delay retries them in lockstep. --speed-limit and
# --speed-time abort an attempt that has trickled below 1KB/s for a minute so
# that it is retried rather than hanging until the job is cancelled, and
# --max-time caps one that stays just above that floor. These assets are all
# well under 100MB - download-data-file.ps1 keeps its own set because the data
# files it fetches are several GB.
$curlFlags = @(
    '--retry', 5, '--retry-all-errors',
    '--connect-timeout', 30,
    '--speed-limit', 1024, '--speed-time', 60,
    '--max-time', 600
)

# The free data files and test evidence come from the data repository,
# https://github.com/51Degrees/data, keyed here by asset name. A file stored
# there as a .link is downloaded by that repository's own script, which follows
# the link, so the download rules live in one place.
$dataFiles = @{
    '51Degrees-LiteV4.1.hash' = 'device-detection/51Degrees-LiteV4.1.hash'
    '20000 Evidence Records.yml' = 'device-detection/20000 Evidence Records.yml'
    '20000 User Agents.csv' = 'device-detection/20000 User Agents.csv'
    '51Degrees-LiteIpiV41.ipi' = 'ip-intelligence/51Degrees-LiteV41.ipi'
    '51Degrees-IPIV4AsnIpiV41.ipi' = 'ip-intelligence/51Degrees-IPIV4AsnIpiV41.ipi'
    'ip-intelligence-evidence.yml' = 'ip-intelligence/evidence.yml'
}
$dataRepository = $null
# Downloads are tried again after a reset connection, as the curl flags above
# do for the other assets.
$DataAttempts = 3
$DataRetrySeconds = 30

function Get-FromData {
    param (
        [Parameter(Mandatory)][string]$Asset,
        [Parameter(Mandatory)][string]$Path
    )
    # One shallow clone serves every asset in this run.
    if (-not $script:dataRepository) {
        $script:dataRepository = Join-Path ([IO.Path]::GetTempPath()) "data-$PID"
        git clone --quiet --depth 1 https://github.com/51Degrees/data.git $script:dataRepository
    }
    $file = Join-Path $script:dataRepository $Path
    if (Test-Path -LiteralPath "$file.link") {
        for ($attempt = 1; ; $attempt++) {
            & (Join-Path $script:dataRepository 'get-data-files.ps1') (Split-Path $Path -Leaf)
            if (-not $LASTEXITCODE) { break }
            if ($attempt -eq $DataAttempts) {
                throw "The data repository's script did not download $Path"
            }
            Start-Sleep -Seconds $DataRetrySeconds
        }
    }
    Copy-Item -LiteralPath $file -Destination (Join-Path $cache $Asset)
}

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
            # A 200 with an empty or truncated body passes curl -f. Accepted,
            # the file is cached for the rest of the day and every consumer
            # reads it as no data, which is what a fetch just after midnight
            # UTC once did to chargify.json.
            $content = Get-Content -Raw $Output
            if (-not $content -or -not (Test-Json -Json $content -ErrorAction SilentlyContinue)) {
                throw "the download is empty or not JSON"
            }
            return
        } catch {
            Write-Warning "$Data $version is not downloadable ($_); trying an older version..."
        }
    }
    throw "No downloadable $Data version found in the last 30 days"
}

foreach ($asset in $Assets) {
    if (Test-Path $cache/$asset) {
        Write-Host "Asset '$asset' already present in cache, skipping download"
        continue
    }
    Write-Host "Fetching '$asset'"
    try {
        if ($dataFiles.ContainsKey($asset)) {
            Get-FromData -Asset $asset -Path $dataFiles[$asset]
            continue
        }
        switch -Exact -CaseSensitive ($asset) {
            "TAC-HashV41.hash" {
                & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -LicenseKey $DeviceDetection -Url $DeviceDetectionUrl
                Move-Item -Path $_ -Destination $cache
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
            "chargify.json" {
                Get-FromBulkData -License:$DeviceDetection -Data 'chargify' -Output $cache/$_
            }
            "entitlement.json" {
                Get-FromBulkData -License:$DeviceDetection -Data 'entitlement' -Output $cache/$_
            }
            default { Write-Error "Unknown asset: $_" }
        }
    } catch {
        # Never leave a partial file behind: the Test-Path check above would
        # take it for a complete asset on the next run.
        if (Test-Path $cache/$asset) {
            Remove-Item -Force $cache/$asset
        }
        throw
    }
}

if ($dataRepository) {
    Remove-Item -Recurse -Force -LiteralPath $dataRepository
}
