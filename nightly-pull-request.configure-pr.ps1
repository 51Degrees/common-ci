param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    # Builds every entry in ci/options.json, even where the repository's
    # ci/select-options.ps1 would choose fewer.
    [bool]$FullMatrix
)
$ErrorActionPreference = "Stop"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Checkout PR"
./steps/checkout-pr.ps1 -RepoName $RepoName -Branch $Branch -PullRequestId $PullRequestId
Write-Output "::endgroup::"

Write-Output "::group::Get Build Options"
$Options = Get-Content $RepoName/ci/options.json -Raw
$Options = $Options -replace "`r?`n", ""
# A repository with ci/select-options.ps1 builds a pull request on the entries
# its changes need. The branch itself, which is pull request 0, and a full
# matrix build every entry.
if ([int]$PullRequestId -ne 0 -and !$FullMatrix -and
    (Test-Path $RepoName/ci/select-options.ps1)) {
    ./steps/select-options.ps1 -RepoName $RepoName -Branch $Branch -Options $Options
}
# This branch builds pull requests without the macOS entries, so that their
# full builds leave the macOS runners free.
$Entries = $Options | ConvertFrom-Json
$Kept = @($Entries | Where-Object { $_.Image -notlike 'macos*' })
Write-Output "Left out $($Entries.Count - $Kept.Count) macOS entries"
$Options = ConvertTo-Json -InputObject $Kept -Compress -Depth 20
Write-Output $Options
Write-Output options=$Options | Out-File $GitHubOutput -Append
# Nothing is built when no entry was chosen, as for a change to documentation
# alone.
$Build = $Options -eq '[]' ? 'false' : 'true'
Write-Output build=$Build | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"
