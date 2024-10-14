param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [string]$Project = ".",
    [string]$Platform = "win-x64",
    [switch]$ShouldCompress
)

$packagesDir = New-Item -ItemType directory -Path package -Force

Push-Location $RepoName
try {
    dotnet publish $Project --nologo --sc -c Release -r $Platform -o publish /p:Version=$Version || $(throw "dotnet publish failed")
    if($ShouldCompress) {
        Compress-Archive -Path publish/* -DestinationPath $packagesDir/$RepoName-$Version.zip
    }
} finally {
    Pop-Location
}
