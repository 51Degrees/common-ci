param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Version
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$packageDir = New-Item -Force -ItemType directory -Path package

Push-Location $RepoName
try {
    Write-Host "Setting workspace versions to $Version"
    # Get the list of all direct package dependencies
    $deps = npm pkg get --json --workspaces dependencies | ConvertFrom-Json -AsHashtable
    $pkgs = $deps.Keys # these are the packages that are members of the workspace
    foreach ($pkg in $deps.GetEnumerator()) {
        foreach ($dep in $pkg.Value.GetEnumerator()) {
            if ($dep.Key -in $pkgs) {
                # If a dependency is a member of the workspace, set its version
                Write-Host "Setting $($pkg.Key) dependency [$($dep.Key) -> $($Version)]"
                npm pkg set -w $pkg.Key "dependencies[$($dep.Key)]=$Version"
            }
        }
    }
    # This also does an npm install, which provides a basic sanity check
    npm version --workspaces --allow-same-version $Version

    Write-Host "Packing packages"
    npm pack --workspaces --pack-destination $packageDir
} finally { Pop-Location }
