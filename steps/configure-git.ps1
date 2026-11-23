param (
    $GitHubUser,
    $GitHubEmail
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The automation token, which the job has in its environment.
if ([string]::IsNullOrWhiteSpace($env:CI_ACCESS_TOKEN)) {
    throw "CI_ACCESS_TOKEN is not set, so git cannot sign in to GitHub."
}

$GitHubUser = $GitHubUser ? $GitHubUser : "Automation51D"
$GitHubEmail = $GitHubEmail ? $GitHubEmail : "CI@51Degrees.com"

# Supply the token through a credential helper rather than embedding it in the
# URL (url.insteadOf). Credentials embedded in the URL are dropped when GitHub
# answers with a redirect, so the request that follows is sent unauthenticated
# and fails with "could not read Username". The helper is looked up per host,
# so it still applies after a redirect. The empty value first clears any
# helpers configured system-wide (e.g. Git Credential Manager on Windows
# runners), which would otherwise be asked first and may try to prompt.
git config --global credential.https://github.com.helper ""
git config --global --add credential.https://github.com.helper "!f() { echo username=x-access-token; echo password=$env:CI_ACCESS_TOKEN; }; f"
git config --global user.email $GitHubEmail
git config --global user.name $GitHubUser
git config --global filter.lfs.smudge "git-lfs smudge --skip -- %f"
git config --global filter.lfs.process "git-lfs filter-process --skip"
git config --global core.longpaths true

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN = $env:CI_ACCESS_TOKEN
