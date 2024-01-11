
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$GitHubUser = "",
    [string]$GitHubEmail = "",
    [Parameter(Mandatory=$true)]
    [Hashtable]$Options,
    [bool]$DryRun = $False
)

. ./constants.ps1

if ($GitHubUser -eq "") {
  $GitHubUser = $DefaultGitUser
}
if ($GitHubEmail -eq "") {
  $GitHubEmail = $DefaultGitEmail
}

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Set-PSDebug -Trace 2

Write-Output "::group::Build Package"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "build-package.ps1" -Options $Options -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
