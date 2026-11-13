param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$Branch
)
# Writes the branch the nightly's own pull requests target and the nightly
# merges into. A repository with an rc branch takes every change to its default
# branch through rc, so for the default branch the answer is rc. Any other
# branch, and any repository without rc, gets $Branch back unchanged.
#
# Fails rather than guessing when GitHub cannot be asked, because answering the
# default branch would let the nightly merge into it.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$default = (gh api "repos/$OrgName/$RepoName" | ConvertFrom-Json).default_branch
if ($Branch -cne $default) {
    Write-Host "'$Branch' is not the default branch '$default', so it is used as it is"
    return $Branch
}

$refs = gh api "repos/$OrgName/$RepoName/git/matching-refs/heads/rc" | ConvertFrom-Json
if (@($refs | Where-Object ref -ceq 'refs/heads/rc').Count -gt 0) {
    Write-Host "$OrgName/$RepoName takes changes to '$default' through rc, so rc is used"
    return 'rc'
}

Write-Host "$OrgName/$RepoName has no rc branch, so '$Branch' is used"
return $Branch
