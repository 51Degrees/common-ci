param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Building '$Name'"
    mvn compile --batch-mode --no-transfer-progress -DskipTests
}
finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}
