param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch,
    [string]$DestinationDir = ""
)

. ./constants.ps1

$TemporaryRepoName = [IO.Path]::Combine($DestinationDir, "b")
$Url = "https://github.com/$OrgName/$RepoName"
$RepoPath = [IO.Path]::Combine($pwd, $TemporaryRepoName)

Write-Output "Cloning '$Url'"
git clone $Url $TemporaryRepoName


Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    if ("" -ne $Branch) {
        # The format %(refname) returns the branches in the format "refs/remotes/[remotename]/[branchname]"
        $branches = $(git branch -a --format "%(refname)")

        if ($branches.Contains("refs/remotes/origin/$Branch")) {

            Write-Output "Checking out branch '$Branch'"
            git checkout $Branch

        }
        else {

            Write-Output "Creating new branch '$Branch'"
            git checkout -b $Branch

        }
    }
    
    Write-Output "Checking out submodules"
    git submodule update --init --recursive

}
finally {
    
    Write-Output "Leaving '$RepoPath'"
    Pop-Location

    Write-Output "Rename temporary directory"
    Rename-Item $RepoPath $RepoName

}
