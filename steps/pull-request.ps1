param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Message,
    [Parameter(Mandatory=$true)]
    [string]$From,
    [string]$To = "main",
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Entering $RepoName"
Push-Location $RepoName
try {
    Write-Output "Getting PRs from '$From' to '$To'"
    $PRs = gh pr list -H $From -B $To --json number --jq '.[].number'

    Write-Output "There are '$($Prs.Count)' PRs"

    if ($PRs.Count -gt 0) {
        Write-Output "A PR already exists for this branch."
    } else {
        gh pr create -H $From -B $To --title $Message --body $Message ($DryRun ? '--dry-run' : $null)
    }

} finally {
    Write-Output "Leaving $RepoName"
    Pop-Location
}

