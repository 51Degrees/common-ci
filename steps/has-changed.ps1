param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# A moved submodule pointer is a change, but edits inside a submodule are
# not: commit-changes cannot stage them, so counting them fails the commit.
$changes = $(git -C $RepoName status --porcelain --ignore-submodules=dirty)
Write-Output "There are $($changes.Count) changes:"
Write-Output $changes

exit $changes.count -gt 0 ? 0 : 1
