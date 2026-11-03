param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version
)

Write-Output "Checking if update is required"
git -C $RepoName show-ref --quiet --tags $Version

if ($LASTEXITCODE -eq 0) {
    Write-Output "Version '$Version' already present, no update needed"
    exit 1
}

# A release that would only carry documentation publishes packages identical to
# the last ones, so it is not an update. Documentation is any Markdown file and
# anything under .github/images. Without a release tag there is nothing to
# compare with, so it is an update as before.
$lastTag = git -C $RepoName describe --tags --abbrev=0 2>$null
if ($LASTEXITCODE -eq 0 -and $lastTag) {
    $changed = @(git -C $RepoName diff --name-only $lastTag HEAD)
    $notDocumentation = @($changed | Where-Object {
        $_ -notmatch '(?i)\.md$' -and $_ -notmatch '^\.github/images/'
    })
    if ($changed.Count -gt 0 -and $notDocumentation.Count -eq 0) {
        Write-Output "Only documentation changed since $lastTag, no update needed"
        exit 1
    }
}

exit 0
