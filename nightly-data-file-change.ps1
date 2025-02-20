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
    [bool]$DryRun = $False
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$PrBranch = "properties-update/$Branch"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName - $Branch"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch -ForceSwitchTo $PrBranch
Write-Output "::endgroup::"

Write-Output "::group::Clone Tools"
./steps/clone-repo.ps1 -RepoName "tools" -OrgName $OrgName
Write-Output "::endgroup::"

Write-Output "::group::Fetch Assets"
# TODO: support caching data files like language-specific fetch-assets scripts
./steps/fetch-hash-assets.ps1 `
    -RepoName tools `
    -LicenseKey $DataKey `
    -DataType $DataType `
    -Product $Product `
    -ArchiveName $FileName `
    -Url $DataUrl
Write-Output "::endgroup::"

Write-Output "::group::Generate Accessors"
./steps/run-script.ps1 ./$RepoName/ci/generate-accessors.ps1 @{
    RepoName = 'tools'
    DataFile = "tools/$FileName" -creplace '\.gz$', ''
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

    Write-Output "::group::PR To Main"
    ./steps/pull-request.ps1 -RepoName $RepoName -From $PrBranch -To $Branch -Message "Update properties" -DryRun $DryRun
    Write-Output "::endgroup::"

} else {
    Write-Host "No property changes, so not creating a pull request."
}

exit # Ignore $LASTEXITCODE here
