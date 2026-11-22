param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [int]$PullRequestId = 0,
    [bool]$SeparateExamples
)

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

if ($PullRequestId -ne 0) {
    ./steps/checkout-pr.ps1 -RepoName $RepoName -PullRequestId $PullRequestId
}

if ($SeparateExamples){
    Write-Output "::group::Clone $RepoName-examples"
    ./steps/clone-repo.ps1 -RepoName "$RepoName-examples" -OrgName $OrgName -Branch $Branch -DestinationDir $RepoName
    Write-Output "::endgroup::"
}

Write-Output "::group::Clone Tools"
./steps/clone-repo.ps1 -RepoName "tools" -OrgName $OrgName
Write-Output "::endgroup::"

if ($RepoName -ne "documentation") {
    Write-Output "::group::Clone Documentation"
    ./steps/clone-repo.ps1 -RepoName "documentation" -OrgName $OrgName -Branch $Branch
    Write-Output "::endgroup::"
} else {
    Write-Output "::group::Remote-Update Documentation Submodules"
    git -C $RepoName submodule update --init --remote
    Write-Output "::endgroup::"
}

Write-Output "::group::Generate Documentation"
./steps/generate-documentation.ps1 -RepoName $RepoName
Write-Output "::endgroup::"
