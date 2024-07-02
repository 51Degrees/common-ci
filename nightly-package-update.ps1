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
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"

$PrBranch = "update-packages/$Branch"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -ForceSwitchTo "$PrBranch"
Write-Output "::endgroup::"

Write-Output "::group::Update Package Dependencies"
./steps/run-script.ps1 ./$RepoName/ci/update-packages.ps1 @{RepoName = $RepoName; DryRun = $DryRun}
Write-Output "::endgroup::"

Write-Output "::group::Check for Changes"
./steps/has-changed.ps1 -RepoName $RepoName
Write-Output "::endgroup::"

if ($LASTEXITCODE -eq 0) {
    Write-Output "::group::Commit Changes"
    ./steps/commit-changes.ps1 -RepoName $RepoName -Message "Update packages"
    Write-Output "::endgroup::"

    Write-Output "::group::Push Changes"
    ./steps/push-changes.ps1 -RepoName $RepoName -DryRun $DryRun -Force $true
    Write-Output "::endgroup::"

    Write-Output "::group::Create Pull Request"
    ./steps/pull-request.ps1 -RepoName $RepoName -From $PrBranch -To $Branch -Message "Update packages" -DryRun $DryRun
    Write-Output "::endgroup::"

} else {
    Write-Output "$($env:CI -eq 'true' ? '::warning::' : '')No package changes, so not creating a pull request."
}

exit # Ignore $LASTEXITCODE here
