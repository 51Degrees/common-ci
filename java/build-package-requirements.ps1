param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name,
    [string[]]$ExtraArgs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Building '$Name'"
    mvn package --batch-mode --no-transfer-progress -DskipTests $ExtraArgs
}
finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}
