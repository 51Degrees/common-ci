param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [switch]$AllowSnapshots
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    Write-Output "Updating dependencies. Patch version only. Snapshots are $($AllowSnapshots ? '' : 'dis')allowed."
    mvn -B versions:update-properties -DallowMinorUpdates=false "-DallowSnapshots=$($AllowSnapshots.ToString().ToLower())" -DgenerateBackupPoms=false

}
finally {
    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
