param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$changes = $(git -C $RepoName status --porcelain)
Write-Output "There are $($changes.Count) changes:"
Write-Output $changes

exit $changes.count -gt 0 ? 0 : 1
