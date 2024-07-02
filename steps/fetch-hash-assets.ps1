
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$LicenseKey,
    [string]$DataType = "HashV41",
    [string]$ArchiveName = "TAC-HashV41.hash.gz",
    [string]$Url = $Null
)

$CommonPath = $pwd
$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    $FileName = [IO.Path]::Combine($pwd, $ArchiveName)
    
    Write-Output "Downloading Hash data file"
    $Result = $(& $CommonPath\steps\download-data-file.ps1 -licenseKey $LicenseKey -dataType $DataType -product "V4TAC" -fullFilePath $FileName -Url $Url)

    if ($Result -eq $False) {

        Write-Error "Failed to download data file"
        exit 1

    }

    Write-Output "Extracting $FileName"
    & $CommonPath\steps\gunzip-file.ps1 -Source $FileName
    
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
