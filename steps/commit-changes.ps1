param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Message
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Adding $($(git -C $RepoName status --porcelain).Count) changes"
git -C $RepoName add .

Write-Output "Committing changes with message '$Message'"
git -C $RepoName commit -m $Message
