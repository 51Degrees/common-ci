
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Branch,
    [bool]$DryRun = $False
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    Write-Output "Pulling"
    $Command = "git pull --rebase origin $Branch"
    if ($DryRun -eq $False) {
        Invoke-Expression $Command
    }
    else {
        Write-Output "Dry run - not executing the following: $Command"
    }
    
    Write-Output "Pushing"
    $Command = "git push origin $Branch"
    if ($DryRun -eq $False) {
        Invoke-Expression $Command
    }
    else {
        Write-Output "Dry run - not executing the following: $Command"
    }

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
