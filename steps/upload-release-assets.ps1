param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    [bool]$DryRun = $False
)

$PackagePath = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$PackagePath'"
Push-Location $PackagePath

try {

    $files = Get-ChildItem "."

    foreach ($file in $files) {

        if ($file.Attributes.Equals([System.IO.FileAttributes]::Directory)) {
            Write-Output "Compressing $($file.Name)"
            Compress-Archive -Path $file -DestinationPath "$($file).zip"
            $file = Get-Item "$($file).zip"
        }
        Write-Output "Uploading $($file.Name)"
        $Command = {gh release upload $Tag $file.Name --repo https://github.com/$OrgName/$RepoName}
        if ($DryRun -eq $False) {
            & $Command
        }
        else {
            Write-Output "Dry run - not executing the following: $Command"
        }
    }

}
finally {

    Write-Output "Leaving '$PackagePath'"
    Pop-Location

}
