param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$LicenseKey,
    [string]$Url,
    [string]$DataType = "HashV41",
    [string]$Product = "V4TAC",
    [string]$ArchiveName = "TAC-HashV41.hash.gz"
)

Write-Host "Downloading $DataType data file"
& $PSScriptRoot/download-data-file.ps1 -LicenseKey $LicenseKey -DataType $DataType -Product $Product -FullFilePath $RepoName/$ArchiveName -Url $Url

Write-Host "Extracting $ArchiveName"
& $PSScriptRoot/gunzip-file.ps1 $RepoName/$ArchiveName
