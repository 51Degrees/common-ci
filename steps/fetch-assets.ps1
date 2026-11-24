param (
    [Parameter(Mandatory)][string[]]$Assets,
    [switch]$FullCsv
)
$ErrorActionPreference = "Stop"

# The licensed files come from the Distributor with the license key in
# _51DEGREES_LICENSE_KEY, which the step that downloads sets from the source
# secret that carries the products. Without it, the step fails naming the
# variable, rather than with the service's refusal.
$licensed = @('TAC-HashV41.hash', '51Degrees-EnterpriseIpiV41.ipi', '51Degrees.csv',
    '51Degrees-Tac.zip')
function Test-Licensed ([string]$Asset) {
    if ($Asset -cnotin $licensed) { return $true }
    return -not [string]::IsNullOrWhiteSpace($env:_51DEGREES_LICENSE_KEY)
}
$PSNativeCommandUseErrorActionPreference = $true

$cache = New-Item -ItemType Directory -Path assets -Force

# The free data files and test evidence come from the data repository,
# https://github.com/51Degrees/data, keyed here by asset name. A file stored
# there as a .link is downloaded by that repository's own script, which follows
# the link, so the download rules live in one place.
$dataFiles = @{
    '51Degrees-LiteV4.1.hash' = 'device-detection/51Degrees-LiteV4.1.hash'
    '20000 Evidence Records.yml' = 'device-detection/20000 Evidence Records.yml'
    '51Degrees-LiteIpiV41.ipi' = 'ip-intelligence/51Degrees-LiteV41.ipi'
    '51Degrees-IPIV4AsnIpiV41.ipi' = 'ip-intelligence/51Degrees-IPIV4AsnIpiV41.ipi'
    'ip-intelligence-evidence.yml' = 'ip-intelligence/evidence.yml'
}
$dataRepository = $null
# Downloads are tried again after a reset connection.
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

foreach ($asset in $Assets) {
    if (Test-Path $cache/$asset) {
        Write-Host "Asset '$asset' already present in cache, skipping download"
        continue
    }
    if (-not (Test-Licensed $asset)) {
        throw "'$asset' needs the data license key, and _51DEGREES_LICENSE_KEY is not set. The step that downloads sets it from the source secret that carries the products, which for the data files is LICENSE_KEY_V4TAC_IPIV4ENTERPRISE."
    }
    Write-Host "Fetching '$asset'"
    try {
        if ($dataFiles.ContainsKey($asset)) {
            Get-FromData -Asset $asset -Path $dataFiles[$asset]
            continue
        }
        switch -Exact -CaseSensitive ($asset) {
            "TAC-HashV41.hash" {
                & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName .
                Move-Item -Path $_ -Destination $cache
            }
            "51Degrees-EnterpriseIpiV41.ipi" {
                & $PSScriptRoot/fetch-hash-assets.ps1 -RepoName . -ArchiveName "$_.gz" -DataType IPIV41 -Product IPIV4Enterprise
                Move-Item -Path $_ -Destination $cache
            }
            "51Degrees.csv" {
                & $PSScriptRoot/download-data-file.ps1 -DataType 'CSV' -Product 'V4TAC' -FullFilePath "$_.zip"
                Expand-Archive -DestinationPath . "$_.zip"
                if ($FullCsv) {
                    Move-Item -Path '51Degrees-Tac-All.csv' -Destination $cache/$_
                } else {
                    Get-Content -TotalCount 1 '51Degrees-Tac-All.csv' > $cache/$_ # Most repos only need the header
                }
                Remove-Item -Force "$_.zip", '51Degrees-Tac-All.csv'
            }
            "51Degrees-Tac.zip" {  # same as the CSV above, without extracting
                & $PSScriptRoot/download-data-file.ps1 -DataType 'CSV' -Product 'V4TAC' -FullFilePath "$cache/$_"
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
