param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [Parameter(Mandatory=$true)]
    [hashtable]$Options,
    [bool]$DryRun = $False
)
$ErrorActionPreference = "Stop"

# Common options
$Options += $PSBoundParameters # Add RepoName, DryRun etc.
if ($Options.Keys) {
    $Options += $Options.Keys # Expand keys into options
}

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Install Package From Artifact"
./steps/run-script.ps1 ./$RepoName/ci/install-package.ps1 $Options
Write-Output "::endgroup::"

Write-Output "::group::Publish Packages"
if ($Branch -ceq "main" -or $Branch -clike "version/*") {
    ./steps/run-script.ps1 ./$RepoName/ci/publish-package.ps1 $Options
} else {
    Write-Output "Not on the main branch, skipping publishing"
}
Write-Output "::endgroup::"

Write-Output "::group::Update Tag"
if ($global:SkipUpdateTag) { # Using a global here so that it can be set by publish-package.ps1
  Write-Output "Tag update skipped"
} else {
  ./steps/update-tag.ps1 -RepoName $RepoName -OrgName $OrgName -Tag $Options.Version -DryRun $DryRun
  ./steps/upload-release-assets.ps1 -RepoName $RepoName -OrgName $OrgName -Tag $Options.Version -DryRun $DryRun
}
Write-Output "::endgroup::"
