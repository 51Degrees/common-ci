param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version
)

. $PSScriptRoot/documentation-pattern.ps1

Write-Output "Checking if update is required"
git -C $RepoName show-ref --quiet --tags $Version

if ($LASTEXITCODE -eq 0) {
    Write-Output "Version '$Version' already present, no update needed"
    exit 1
}

# A release that would only carry documentation or repository settings
# publishes packages identical to the last ones, so it is not an update. That is
# the documentation $DocumentationPattern matches and anything under .github,
# which holds the workflows, images and templates. No package includes any of
# them. Without a release tag there is nothing to compare with, so it is an
# update as before.
$lastTag = git -C $RepoName describe --tags --abbrev=0 2>$null
if ($LASTEXITCODE -eq 0 -and $lastTag) {
    $changed = @(git -C $RepoName diff --name-only $lastTag HEAD)
    $packageFiles = @($changed | Where-Object {
        $_ -notmatch $DocumentationPattern -and $_ -notmatch '^\.github/'
    })
    if ($changed.Count -gt 0 -and $packageFiles.Count -eq 0) {
        Write-Output "Only documentation and .github files changed since $lastTag, no update needed"
        exit 1
    }
}

exit 0
