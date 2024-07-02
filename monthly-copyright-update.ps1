param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [Parameter(Mandatory=$true)]
    [string]$GitHubUser,
    [Parameter(Mandatory=$true)]
    [string]$GitHubEmail,
    [string]$GitHubToken,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

$PrBranch = "update-copyright/$Branch"

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName - $Branch"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -ForceSwitchTo $PrBranch
Write-Output "::endgroup::"

Write-Output "::group::Clone Tools"
./steps/clone-repo.ps1 -RepoName "tools" -OrgName $OrgName
Write-Output "::endgroup::"

Write-Output "::group::Update Copyright"
./steps/run-script.ps1 ./tools/ci/update-copyright.ps1 @{RepoName = tools; TargetRepo = $RepoName}
Write-Output "::endgroup::"

Write-Output "::group::Has Changed"
./steps/has-changed.ps1 -RepoName $RepoName
Write-Output "::endgroup::"

if ($LASTEXITCODE -eq 0) {
    Write-Output "::group::Commit Changes"
    ./steps/commit-changes.ps1 -RepoName $RepoName -Message "Update copyright"
    Write-Output "::endgroup::"

    Write-Output "::group::Push Changes"
    ./steps/push-changes.ps1 -RepoName $RepoName -DryRun $DryRun -Force $true
    Write-Output "::endgroup::"

    Write-Output "::group::PR To Main"
    ./steps/pull-request.ps1 -RepoName $RepoName -From $PrBranch -To $Branch -Message "Update copyright" -DryRun $DryRun
    Write-Output "::endgroup::"

} else {
    Write-Host "No copyright changes, so not creating a pull request."
}

exit # Ignore $LASTEXITCODE here
