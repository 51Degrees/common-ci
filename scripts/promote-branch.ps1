param (
    [Parameter(Mandatory)][string[]]$Repositories,
    [string]$NewVersion = "4.5",
    [string]$OldVersion,
    [string]$BaseUri = "git@github.com:51Degrees",
    [string]$User = "Automation51D",
    [string]$Email = "51DCI@51Degrees.com"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function Test-PromotedVersion {
    $PSNativeCommandUseErrorActionPreference = $false
    git -C $repo show-ref "refs/heads/version/$NewVersion"
    return $LASTEXITCODE -eq 0
}

foreach ($repo in $Repositories) {
    Write-Host "Cloning $repo..."
    git clone --quiet --bare --filter=tree:0 "$BaseUri/$repo" $repo
    $version = $OldVersion ? $OldVersion : (git -C "$repo" describe --tags --abbrev=0) -replace '\.\d+$', ''
    Write-Host "  saving main to release/$version"
    git -C $repo branch "release/$version"
    if (Test-PromotedVersion) {
        # version/$NewVersion exists
        Write-Host "  resetting main to version/$NewVersion"
        git -C $repo branch --force main "version/$NewVersion"
        Write-Host "  pushing changes..."
        git -C $repo push --quiet --atomic --force origin "release/$version" main
    } else {
        # version/$NewVersion doesn't exist, create a new commit and tag it with $NewVersion
        Write-Host "  creating an empty bump commit, a tree for it will be auto-downloaded"
        $currentCommit = git -C $repo rev-parse HEAD
        $currentTree = git -C $repo rev-parse 'HEAD^{tree}'
        $newCommit = git -C $repo -c "user.name=$User" -c "user.email=$Email" commit-tree -m "Bump version to $NewVersion" -p $currentCommit $currentTree
        Write-Host "  updating the branch"
        git -C $repo update-ref HEAD $newCommit $currentCommit
        git -C $repo tag "$NewVersion.0"
        Write-Host "  pushing changes..."
        git -C $repo push --quiet --atomic origin HEAD "release/$version" tag "$NewVersion.0"
    }
    Remove-Item -Recurse -Force $repo
}
