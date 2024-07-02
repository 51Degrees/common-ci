param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [string]$GitHubToken,
    [bool]$SeparateExamples
)

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

if ($SeparateExamples){
    $ExamplesRepo = "$RepoName-examples"

    Write-Output "::group::Clone $ExamplesRepo"
    ./steps/clone-repo.ps1 -RepoName $ExamplesRepo -OrgName $OrgName -Branch $Branch -DestinationDir $RepoName/$ExamplesRepo
    Write-Output "::endgroup::"
}

Write-Output "::group::Clone Tools"
./steps/clone-repo.ps1 -RepoName "tools" -OrgName $OrgName
Write-Output "::endgroup::"

if ($RepoName -ne "documentation") {
    Write-Output "::group::Clone Documentation"
    ./steps/clone-repo.ps1 -RepoName "documentation" -OrgName $OrgName -Branch $Branch
    Write-Output "::endgroup::"
}

Write-Output "::group::Generate Documentation"
./steps/generate-documentation.ps1 -RepoName $RepoName
Write-Output "::endgroup::"
