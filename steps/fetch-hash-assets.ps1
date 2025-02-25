param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$LicenseKey,
    [string]$DataType = "HashV41",
    [string]$Product = "V4TAC",
    [string]$ArchiveName = "TAC-HashV41.hash.gz",
    [string]$Url
)

Write-Host "Downloading $DataType data file"
./steps/download-data-file.ps1 -LicenseKey $LicenseKey -DataType $DataType -Product $Product -FullFilePath $RepoName/$FileName -Url $Url

Write-Host "Extracting $FileName"
./steps/gunzip-file.ps1 $RepoName/$FileName
