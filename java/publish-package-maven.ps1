param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$MavenSettings,
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    # We need to set the version here again even though the packages are already built using the next version
    # as this script will run in a new job and the repo will be cloned again.
    Write-Output "Setting version to '$Version'"
    mvn -B versions:set -DnewVersion="$Version"

    $settingsFile = "stagingsettings.xml"

    Write-Output "Writing Settings File"
    $SettingsContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($MavenSettings))
    Set-Content -Path $SettingsFile -Value $SettingsContent
    $SettingsPath = [IO.Path]::Combine($RepoPath, $SettingsFile)

    $ArtifactId = mvn help:evaluate "-Dexpression=project.artifactId" -q -DforceStdout
    $GroupId = mvn help:evaluate "-Dexpression=project.groupId" -q -DforceStdout
    $GroupId = $GroupId.Replace(".", "/")
    $URL = "https://repo1.maven.org/maven2/$GroupId/$ArtifactId/$Version"
    $Request = Invoke-WebRequest -Uri $URL -Method GET -SkipHttpErrorCheck

    if ($Request.StatusCode -eq "404"){

        Write-Output "Deploying to Nexus staging"

        mvn -B nexus-staging:deploy-staged `
            -s $SettingsPath  `
            -f pom.xml `
            -DXmx2048m `
            -DskipTests `
            --no-transfer-progress `
            "-Dhttps.protocols=TLSv1.2" `
            "-DfailIfNoTests=false"

        #if ($Version -cnotmatch '-alpha(\.\d+)?$') {

        Write-Output "Releasing from Nexus to Maven central"
        mvn -B nexus-staging:release `
            -s $SettingsPath  `
            -f pom.xml `
            -DXmx2048m `
            -DskipTests `
            --no-transfer-progress `
            "-Dhttps.protocols=TLSv1.2" `
            "-DfailIfNoTests=false"


        #}
    }
    else{

        Write-Output "Skipping release. The package has already been released. "
    }
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
