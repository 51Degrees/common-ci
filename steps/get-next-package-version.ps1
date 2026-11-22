param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Config = "$PSScriptRoot/../GitVersion.yml",
    [string]$Format = '{SemVer}'
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

& $PSScriptRoot/install-gitversion.ps1

dotnet-gitversion $RepoName /config $Config /format $Format
