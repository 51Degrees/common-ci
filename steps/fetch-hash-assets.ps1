param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$DataType = "HashV41",
    [string]$Product = "V4TAC",
    [string]$ArchiveName = "TAC-HashV41.hash.gz"
)

# The data file comes from the Distributor with _51DEGREES_LICENSE_KEY, which
# download-data-file.ps1 reads from the environment.
Write-Host "Downloading $DataType data file"
& $PSScriptRoot/download-data-file.ps1 -DataType $DataType -Product $Product -FullFilePath $RepoName/$ArchiveName

Write-Host "Extracting $ArchiveName"
& $PSScriptRoot/gunzip-file.ps1 $RepoName/$ArchiveName

Write-Host "Removing $ArchiveName"
Remove-Item -Force $ArchiveName