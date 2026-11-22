param(
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [Hashtable]$Keys,
    [string]$DryRun
)

try {
    $Tag = "$($Keys.DockerRegistry)/$($Keys.DockerContainer):$Version"

    # Login to Dockerhub
    Write-Output "Logging in to docker hub"
    docker login -u $Keys.DockerUser -p $Keys.DockerPassword
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Push to repository when dryrun is false
    $Command = {docker push $Tag}
    if ($DryRun -eq $False) {
        Write-Output "Pushing docker image $Tag"
        & $Command
    } else {
        Write-Output "Dry run - not executing the following: $Command"
    }
}
finally {
    Write-Output "Logging out of docker hub"
    docker logout
}

exit $LASTEXITCODE
