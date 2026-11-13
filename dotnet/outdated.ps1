param (
    [Parameter(Mandatory)][string]$RepoName,
    # Optional solution/project to restore and update. Repositories whose root
    # contains more than one solution must set this so 'dotnet restore' is not
    # ambiguous; when empty both commands operate on the whole directory as before.
    [string]$Target,
    [string[]]$ExtraArgs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Installing dotnet-outdated tool"
dotnet tool install --global dotnet-outdated-tool

# Only forward $Target to the tools when it is actually set, so the default
# behaviour (whole-directory restore/update) is completely unchanged.
$TargetArgs = $Target ? @($Target) : @()

Push-Location $RepoName
try {
    Write-Host "Restoring project"
    dotnet restore @TargetArgs

    Write-Host "Upgrading packages"
    dotnet-outdated --recursive --upgrade --no-restore --version-lock Minor @TargetArgs @ExtraArgs
} finally {
    Pop-Location
}
