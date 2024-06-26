
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    Write-Output "Updating dependencies. Patch version only"
    mvn -B versions:update-properties -DallowMinorUpdates=false -DgenerateBackupPoms=false

}
finally {
    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
