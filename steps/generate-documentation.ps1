param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$DocsPath = "$PWD/$RepoName/docs"
$DoxyGenPath = "$PWD/tools/DoxyGen"
$DoxyGen = "$DoxyGenPath/doxygen"

Write-Output "Setting up requirements"
sudo apt-get install -y graphviz flex bison

Write-Output "Entering '$DoxyGenPath'"
Push-Location $DoxyGenPath
try {
    Write-Output "Extracting DoxyGen executable"
    unzip -o doxygen-linux.zip
    Move-Item doxygen-linux $DoxyGen -Force

} finally {
    Write-Output "Leaving '$DoxyGenPath'"
    Pop-Location
}

Write-Output "Marking '$DoxyGen' as executable"
chmod +x $DoxyGen

Write-Output "Entering '$DocsPath'"
Push-Location $DocsPath
try {
    Write-Output "Running DoxyGen"
    & $DoxyGen

} finally {
    Write-Output "Leaving '$DocsPath'"
    Pop-Location
}

Write-Output "Entering '$RepoName'"
Push-Location $RepoName
try {
    $VersionPath = Get-ChildItem -Filter "4.*"
    Write-Output "Moving $($VersionPath.FullName)"
    Move-Item $VersionPath.FullName "$($VersionPath.FullName)-new"

    $branch = "gh-pages"
    Write-Output "Switching to branch '$branch'"
    & {
        $PSNativeCommandUseErrorActionPreference = $false
        git show-ref --quiet $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Output "Creating new orphan branch"
        }
    }
    git switch --recurse-submodules ($LASTEXITCODE -ne 0 ? '--orphan' : $null) $branch

    if (Test-Path $VersionPath) {
        Write-Output "Removing existing docs in $($VersionPath.FullName)"
        Remove-Item -Recurse -Path $VersionPath.FullName
    }
    if (!(Test-Path ".nojekyll")) {
        Write-Output "Creating a .nojekyll file"
        Write-Output "" > .nojekyll
        git add .nojekyll
    }
    Write-Output "Moving $($VersionPath.FullName)-new back to original location"
    Move-Item "$($VersionPath.FullName)-new" $VersionPath.FullName

} finally {
    Write-Output "Leaving $RepoName"
    Pop-Location
}
