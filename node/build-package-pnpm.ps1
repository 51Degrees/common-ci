param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Version
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$packageDir = New-Item -Force -ItemType directory -Path package

Write-Host "Setting version to $Version"
pnpm -C $RepoName version -r $Version

Write-Host "Packing packages"
pnpm -C $RepoName pack -r --pack-destination $packageDir
