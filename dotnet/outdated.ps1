param (
    [Parameter(Mandatory)][string]$RepoName,
    [string[]]$ExtraArgs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Installing dotnet-outdated tool"
dotnet tool install --global dotnet-outdated-tool

Push-Location $RepoName
try {
    Write-Host "Restoring project"
    dotnet restore

    Write-Host "Upgrading packages"
    dotnet-outdated --recursive --upgrade --no-restore --version-lock Minor @ExtraArgs
} finally {
    Pop-Location
}
