param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$GitHubToken,
    [Parameter(Mandatory)][hashtable]$Options,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

# Common options
$Options += $PSBoundParameters # Add RepoName, DryRun etc.
if ($Options.Keys) {
    $Options += $Options.Keys # Expand keys into options
}

Write-Host "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Host "::endgroup::"

Write-Host "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Host "::endgroup::"

Write-Host "::group::Install Package From Artifact"
./steps/run-script.ps1 ./$RepoName/ci/install-package.ps1 $Options
Write-Host "::endgroup::"

Write-Host "::group::Publish Packages"
if ($Branch -ceq "main" -or $Branch -ceq "alpha" -or $Branch -clike "version/*") {
    ./steps/run-script.ps1 ./$RepoName/ci/publish-package.ps1 $Options
} else {
    Write-Host "Not on the main branch, skipping publishing"
}
Write-Host "::endgroup::"

Write-Host "::group::Update Tag"
if ($global:SkipUpdateTag) { # Using a global here so that it can be set by publish-package.ps1
  Write-Host "Tag update skipped"
} else {
  ./steps/update-tag.ps1 -RepoName $RepoName -OrgName $OrgName -Tag $Options.Version -DryRun $DryRun
  ./steps/upload-release-assets.ps1 -RepoName $RepoName -OrgName $OrgName -Tag $Options.Version -DryRun $DryRun
}
Write-Host "::endgroup::"
