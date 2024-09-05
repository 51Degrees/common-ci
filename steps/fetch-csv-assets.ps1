
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$LicenseKey,
    [string]$Url = $Null
)

$CommonPath = $pwd
$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    $FileName = [IO.Path]::Combine($pwd, "51Degrees-Tac.zip")
    
    Write-Output "Downloading CSV data file"
    $Result = $(& $CommonPath\steps\download-data-file.ps1 -licenseKey $LicenseKey -dataType "CSV" -product "V4TAC" -fullFilePath $FileName -Url $Url)

    if ($Result -eq $False) {

        Write-Error "Failed to download data file"
        exit 1

    }

    Write-Output "Extracting $FileName"
    Expand-Archive -Path $FileName
     
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
