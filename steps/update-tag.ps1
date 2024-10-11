param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Tagging '$Tag'"
git -C $RepoName tag $Tag

if ($DryRun) {
    Write-Output "Dry run - not pushing tag '$Tag'"
    Write-Output "Dry run - not creating a release"
} else {
    Write-Output "Pushing tag '$Tag'"
    git -C $RepoName push origin $Tag

    Write-Output "Creating a GitHub release"
    gh -R $OrgName/$RepoName release create --verify-tag --generate-notes ($Tag -cmatch '-alpha(\.\d+)?$' ? '--prerelease' : $null) $Tag
}
