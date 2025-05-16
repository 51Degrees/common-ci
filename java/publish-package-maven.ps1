param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$MavenSettings
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$mvnSettings = "$PWD/java/settings.xml"

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    # We need to set the version here again even though the packages are already built using the next version
    # as this script will run in a new job and the repo will be cloned again.
    Write-Host "Setting version to '$Version'"
    mvn -B versions:set "-DnewVersion=$Version"

    $env:MVN_CENTRAL_USERNAME, $env:MVN_CENTRAL_PASSWORD = $MavenSettings -split ' ', 2
    $env:MAVEN_OPTS='--add-opens=java.base/java.util=ALL-UNNAMED'

    Write-Host "Releasing to Maven central"
    mvn deploy --batch-mode --no-transfer-progress --settings $mvnSettings -DskipTests 
} finally {
    Write-Host "Leaving '$RepoPath'"
    Pop-Location
}
