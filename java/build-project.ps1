param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $RepoName
try {
    Write-Host "Building $Name..."
    mvn install --batch-mode --no-transfer-progress -DskipTests 
} finally {
    Pop-Location
}
