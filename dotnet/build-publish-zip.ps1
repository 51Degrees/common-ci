param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [string]$Project = "."
)

$packagesDir = New-Item -ItemType directory -Path package -Force

Push-Location $RepoName
try {
    dotnet publish $Project --nologo --sc -c Release -r win-x64 -o publish || $(throw "dotnet publish failed")
    Compress-Archive -Path publish/* -DestinationPath $packagesDir/$RepoName-$Version.zip
} finally {
    Pop-Location
}
