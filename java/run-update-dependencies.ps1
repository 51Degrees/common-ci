param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name,
    [switch]$AllowSnapshots,
    [string[]]$ExtraArgs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Updating dependencies. Patch version only. Snapshots are $($AllowSnapshots ? '' : 'dis')allowed."
    mvn versions:update-properties --batch-mode --no-transfer-progress `
        "-DallowMinorUpdates=false" `
        "-DallowSnapshots=$($AllowSnapshots.ToString().ToLower())" `
        "-DgenerateBackupPoms=false" $ExtraArgs
}
finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}
