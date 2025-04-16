param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [string]$GitHubToken,
    [bool]$DryRun,
    [bool]$SeparateExamples
)
$ErrorActionPreference = "Stop"

./generate-documentation.ps1 `
    -RepoName $RepoName `
    -OrgName $OrgName `
    -Branch $Branch, `
    -GitHubUser $GitHubUser `
    -GitHubEmail $GitHubEmail `
    -GitHubToken $GitHubToken `
    -SeparateExamples $SeparateExamples

if ($SeparateExamples) {
    $ExamplesPath = "$RepoName/$RepoName-examples"
    Write-Output "::group::Removing $ExamplesPath"
    Remove-Item $ExamplesPath -Recurse -Force
    Write-Output "::endgroup::"
}

Write-Output "::group::Has Changed"
./steps/has-changed.ps1 -RepoName $RepoName
Write-Output "::endgroup::"

if ($LASTEXITCODE -eq 0) {
    Write-Output "::group::Commit Changes"
    ./steps/commit-changes.ps1 -RepoName $RepoName -Message "Update documentation from $Branch"
    Write-Output "::endgroup::"

    Write-Output "::group::Push Changes"
    ./steps/push-changes.ps1 -RepoName $RepoName -DryRun $DryRun
    Write-Output "::endgroup::"
    
} else {
    Write-Host "No property changes, so not pushing changes."
}

exit # Ignore $LASTEXITCODE here
