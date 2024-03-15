
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [Parameter(Mandatory=$true)]
    [string]$ApiKey
)

./publish-package-nuget.ps1 `
    -RepoName $RepoName `
    -ProjectDir $ProjectDir `
    -Name $Name `
    -ApiKey $ApiKey `
    -Source "https://nuget.pkg.github.com/$OrgName/index.json"
