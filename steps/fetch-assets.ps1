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
# https://github.com/51Degrees/data, keyed in free-assets.psd1 by asset name.
# A file stored there as a .link is downloaded by that repository's own
# script, which follows the link, so the download rules live in one place.
$dataFiles = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'free-assets.psd1')
$dataRepository = $null
# Downloads are tried again after a reset connection.
$DataAttempts = 3
$DataRetrySeconds = 30

function Get-FromData {
    param (
        [Parameter(Mandatory)][string]$Asset,
        [Parameter(Mandatory)][string]$Path
    )
    if (-not $script:dataRepository) {
        $script:dataRepository = & $PSScriptRoot/data-repository.ps1
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
                # The archive holds an export for each component beside the
                # one for all of them, so it is expanded in a folder of its
                # own and only the asset is kept.
                $archive = New-Item -ItemType Directory `
                    -Path (Join-Path ([IO.Path]::GetTempPath()) "csv-$(New-Guid)")
                try {
                    & $PSScriptRoot/download-data-file.ps1 -DataType 'CSV' -Product 'V4TAC' -FullFilePath "$archive/$asset.zip"
                    Expand-Archive -DestinationPath $archive "$archive/$asset.zip"
                    $all = Join-Path $archive '51Degrees-Tac-All.csv'
                    if ($FullCsv) {
                        Move-Item -LiteralPath $all -Destination $cache/$asset
                    } else {
                        Get-Content -TotalCount 1 -LiteralPath $all > $cache/$asset # Most repos only need the header
                    }
                } finally {
                    Remove-Item -Recurse -Force -LiteralPath $archive
                }
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

# In GitHub Actions the clone stays for the rest of the job.
if ($dataRepository -and -not $env:RUNNER_TEMP) {
    Remove-Item -Recurse -Force -LiteralPath $dataRepository
}
