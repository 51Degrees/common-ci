param (
    [Parameter(Mandatory)][string]$MavenSettings,
    $RepoName, # accepted for compatibility
    $Version,  # accepted for compatibility
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$args = @{
    ConnectionTimeoutSeconds = 30
    OperationTimeoutSeconds = 30
    Method = 'Post'
    Headers = @{Authorization = "Bearer $MavenSettings"}
}
$api = "https://central.sonatype.com/api/v1/publisher"

$bundle = Get-Item package/central-bundle.zip

if ($DryRun) {
    Write-Host "Dry run - not uploading '$($bundle.Name)' ($($bundle.Length) bytes) to $api"
    exit 0
}

Write-Host "Uploading the bundle..."
$id = Invoke-WebRequest @args -Uri "$api/upload" -Form @{bundle = $bundle; publishingType = 'AUTOMATIC'}
Write-Host "Deployment id: $id"

for ($i = 1; $i -le 60; ++$i) {
    Start-Sleep -Seconds 10

    Write-Host "Checking status ($i)..."
    $resp = Invoke-WebRequest @args -Uri "$api/status?id=$id" | ConvertFrom-Json

    switch -Wildcard ($resp.deploymentState) {
        # shouldn't happen due to publishingType being set above, but just in case
        'VALIDATED' {Write-Error "Deployment has passed validation and is waiting on a user to manually publish via the Central Portal UI"}
        'FAILED'    {Write-Error "Publishing failed: $($resp.errors | ConvertTo-Json)"}
        'PUBLISH*' {Write-Host "Deployment successful: $_"; exit 0}
    }
    # Retry on other statuses
}
Write-Error "Reached maximum number of retries, giving up"
