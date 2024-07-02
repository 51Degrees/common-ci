param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$files = Get-ChildItem "package"

if ($files.count -eq 0 -or ($files.Count -eq 1 -and $files[0].Name -eq "dummy.txt")) {
    Write-Output "No files to upload."
    return
}

foreach ($file in $files) {
    if ($file.PSIsContainer) {
        $archive = "package/$($file.Name).zip"
        Write-Output "Compressing '$($file.Name)' to '$archive'"
        Compress-Archive -Path $file -DestinationPath $archive
        $file = Get-Item $archive
    }

    if ($DryRun) {
        Write-Output "Dry run - not uploading '$($file.Name)'"
    } else {
        Write-Output "Uploading $($file.Name)"
        gh release upload $Tag $file --repo https://github.com/$OrgName/$RepoName
    }
}
