param (
    [Parameter(Mandatory=$true)]
    $GitHubToken,
    $GitHubUser,
    $GitHubEmail
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$GitHubUser = $GitHubUser ? $GitHubUser : "Automation51D"
$GitHubEmail = $GitHubEmail ? $GitHubEmail : "CI@51Degrees.com"

git config --global url.https://$GitHubToken@github.com/.insteadOf https://github.com/
git config --global user.email $GitHubEmail
git config --global user.name $GitHubUser
git config --global filter.lfs.smudge "git-lfs smudge --skip -- %f"
git config --global filter.lfs.process "git-lfs filter-process --skip"
git config --global core.longpaths true

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"
