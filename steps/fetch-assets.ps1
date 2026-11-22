param (
    [Parameter(Mandatory)][string[]]$Assets,
    # The licence key for the data files, which come from the Distributor.
    # The shared workflows export it as _51DEGREES_LICENSE_KEY before this
    # runs.
    [string]$LicenseKey = $env:_51DEGREES_LICENSE_KEY,
    [switch]$FullCsv,
    # The old keys and addresses, which a calling repository's main still
    # passes by name until it passes 'secrets: inherit'. Each is read only
    # when _51DEGREES_LICENSE_KEY has no value, and then as it was before that
    # name, so a caller not yet moved keeps working. When
    # _51DEGREES_LICENSE_KEY is set, none of them is read.
    [string]$DeviceDetection,
    [string]$DeviceDetectionUrl,
    [string]$IpIntelligence,
    [string]$IpIntelligenceUrl,
    [string]$CsvUrl
)
$ErrorActionPreference = "Stop"

function Test-Given ([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value)
}

# With _51DEGREES_LICENSE_KEY, every licensed file comes from the Distributor
# with that key, and the old keys and addresses are not read. Without it, the
# old ones are used as they were before, for a caller not yet moved.
if (Test-Given $LicenseKey) {
    $DeviceDetection = $LicenseKey
    $DeviceDetectionUrl = ''
    $IpIntelligence = $LicenseKey
    $IpIntelligenceUrl = ''
    $CsvUrl = ''
}
elseif (@($DeviceDetection, $DeviceDetectionUrl, $IpIntelligence, $IpIntelligenceUrl, $CsvUrl).Where({ Test-Given $_ })) {
    Write-Host "_51DEGREES_LICENSE_KEY is not set, so the old keys and addresses passed are used, as before that name. They go when the calling workflow passes 'secrets: inherit'."
}

# An asset named <name>.json, in lower case letters, digits, and hyphens, is
# the bulkdata data source <name>.
$dataSourceAsset = '^[a-z0-9][a-z0-9-]*\.json$'

# Whether an asset that needs a licence has one: _51DEGREES_LICENSE_KEY, or
# for a caller not yet moved the old key or address for it. Without one, the
# step fails naming the variable, rather than with the Distributor's refusal.
function Test-Licensed ([string]$Asset) {
    switch -Exact -CaseSensitive ($Asset) {
        'TAC-HashV41.hash' { return (Test-Given $DeviceDetection) -or (Test-Given $DeviceDetectionUrl) }
        '51Degrees-EnterpriseIpiV41.ipi' { return (Test-Given $IpIntelligence) -or (Test-Given $IpIntelligenceUrl) }
        '51Degrees.csv' { return (Test-Given $DeviceDetection) -or (Test-Given $CsvUrl) }
        '51Degrees-Tac.zip' { return (Test-Given $DeviceDetection) -or (Test-Given $CsvUrl) }
        { $_ -cmatch $dataSourceAsset } { return Test-Given $DeviceDetection }
        default { return $true }
    }
}
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
            # The script sets an exit code only when it fails, so any earlier
            # code is cleared first.
            $global:LASTEXITCODE = 0
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
    if (-not (Test-Licensed $asset)) {
        throw "'$asset' needs the data licence key, and _51DEGREES_LICENSE_KEY is not set. It is an organisation secret, which the calling workflow passes with 'secrets: inherit'."
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
                # This file came only from an address in a secret. Data files
                # now come from the Distributor with _51DEGREES_LICENSE_KEY,
                # and no Distributor product for it is known yet, so it comes
                # only from the old address of a caller not yet moved.
                if (Test-Given $IpIntelligenceUrl) {
                    & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -Url $IpIntelligenceUrl
                    Move-Item -Path $_ -Destination $cache
                } else {
                    Write-Host "No Distributor product is known for '$_': skipping it. Tests that need it should skip and say so."
                }
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
            # A data source is fetched newest day first, so a new one needs
            # no change here.
            { $_ -cmatch $dataSourceAsset } {
                Get-FromBulkData -License:$DeviceDetection -Data ($_ -creplace '\.json$', '') -Output $cache/$_
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
