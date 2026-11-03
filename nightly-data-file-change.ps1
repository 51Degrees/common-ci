param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [string]$DataKey,
    [string]$DataUrl,
    [string]$DataType = "HashV41",
    [string]$Product = "V4TAC",
    [string]$FileName = "TAC-HashV41.hash.gz",
    [string]$GitHubToken,
    [string]$MetadataBranch = "main", # unused, kept for compatibility
    [string]$ToolsBranch = "main",
    [bool]$DryRun = $False,
    # The branch the changes are pushed to and proposed from. A repository that
    # runs this for more than one data type gives each type its own branch.
    [string]$PrBranch
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

# The pull request targets rc where the repository takes changes through rc.
$Branch = ./steps/get-target-branch.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
if (-not $PrBranch) {
    $PrBranch = "properties-update/$Branch"
}

Write-Output "::group::Clone $RepoName - $Branch"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -ForceSwitchTo $PrBranch
Write-Output "::endgroup::"

Write-Output "::group::Clone Tools"
./steps/clone-repo.ps1 -RepoName "tools" -OrgName $OrgName -Branch $ToolsBranch
Write-Output "::endgroup::"

Write-Output "::group::Setup Environment"
./tools/ci/setup-environment.ps1 -NugetUser $GitHubUser -NugetPassword $GitHubToken
Write-Output "::endgroup::"

Write-Output "::group::Generate Accessors"
./steps/run-script.ps1 ./$RepoName/ci/generate-accessors.ps1 @{
    RepoName = 'tools'
    DataType = $DataType
}
Write-Output "::endgroup::"

Write-Output "::group::Has Changed"
./steps/has-changed.ps1 -RepoName $RepoName
Write-Output "::endgroup::"

if ($LASTEXITCODE -eq 0) {
    Write-Output "::group::Commit Changes"
    ./steps/commit-changes.ps1 -RepoName $RepoName -Message "Update properties"
    Write-Output "::endgroup::"
    
    Write-Output "::group::Push Changes"
    ./steps/push-changes.ps1 -RepoName $RepoName -DryRun $DryRun -Force $true
    Write-Output "::endgroup::"

    Write-Output "::group::Create Pull Request"
    ./steps/pull-request.ps1 -RepoName $RepoName -From $PrBranch -To $Branch -Message "Update properties" -DryRun $DryRun
    Write-Output "::endgroup::"

} else {
    Write-Host "No property changes, so not creating a pull request."
}

exit # Ignore $LASTEXITCODE here
