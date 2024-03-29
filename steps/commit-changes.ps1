
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Message
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    Write-Output "Adding '$($(git diff -s).count)' changes"
    git add *

    Write-Output "Committing changes with message '$Message'"
    git commit -m $Message
    
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}