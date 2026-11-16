param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version
)

. $PSScriptRoot/documentation-pattern.ps1
. $PSScriptRoot/version-tags.ps1

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
# them. The last release is the highest release tag of any package on HEAD or
# before it, as version-tags.ps1 reads them. Without one there is nothing to
# compare with, so it is an update.
$lastTag = @(Get-VersionTags $RepoName -AnyPrefix -Merged)[-1].Tag
if ($lastTag) {
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
