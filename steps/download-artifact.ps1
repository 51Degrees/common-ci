
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    $RunId,
    [Parameter(Mandatory=$true)]
    [string]$ArtifactName
)

$Response = gh api /repos/$OrgName/$RepoName/actions/runs/$RunId/artifacts
$Artifacts = $($Response | ConvertFrom-Json).artifacts
Write-Output $Response
Write-Output $Artifacts

foreach ($Artifact in $Artifacts) {
    if ($Artifact.name -eq $ArtifactName) {
        Write-Output "Downloading '$ArtifactName'"

        Invoke-WebRequest -Uri $Artifact.archive_download_url -Headers @{"Authorization" = "Bearer $env:_51DEGREES_ACCESS_TOKEN"} -Outfile "$ArtifactName.zip"
        exit 0
    }
}

Write-Output "Artifact '$ArtifactName' not found for run '$RunId'"
exit 1
