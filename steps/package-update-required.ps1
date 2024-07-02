param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version
)

Write-Output "Checking if update is required"
git -C $RepoName show-ref --quiet --tags $Version

if ($LASTEXITCODE -gt 0) {
    exit 0
}

Write-Output "Version '$Version' already present, no update needed"
exit 1
