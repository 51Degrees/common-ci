param(
    [string]$RepoName,
    [string]$OrgName,
    [int]$Id,
    [string]$Message
)

# This token is used by the hub command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN = $env:_51DEGREES_ACCESS_TOKEN

gh api /repos/$OrgName/$RepoName/issues/$Id/comments -X POST -f "body=$Message"
