param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$Branch = "main",
    [string]$GitHubUser,
    [string]$GitHubEmail,
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [bool]$DryRun,
    [string]$BuildPlatform = "ubuntu-latest"
)
$ErrorActionPreference = "Stop"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

Write-Output "::group::Get Next Package Version"
./steps/run-script.ps1 ./$RepoName/ci/get-next-package-version.ps1 @{RepoName = $RepoName; VariableName = "Version"}
Write-Output version=$Version
if (!($Version -cmatch '^v?\d+\.\d+\.\d+(\.\d+)?(-[\w-]+(\.\d+)?)?$')) {
  Write-Error "Version '$Version' isn't valid"
  exit 1
}
Write-Output version=$Version | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"

Write-Output "::group::Package Update Required"
# A repository that releases several packages, each with its own version and
# tagged '<package>/<version>', cannot answer this from one version: a plain
# tag lookup would find another package's tag of the same number. Such a
# repository decides for itself, in its own ci/package-update-required.ps1,
# with the same exit codes: 0 when something is to be released, 1 when not.
$global:LASTEXITCODE = 0
if (Test-Path ./$RepoName/ci/package-update-required.ps1) {
  & ./$RepoName/ci/package-update-required.ps1 -RepoName $RepoName -Version $Version
} else {
  ./steps/package-update-required.ps1 -RepoName $RepoName -Version $Version
}
Write-Output "update_required=$($LASTEXITCODE -eq 0 ? 'true' : 'false')" | Out-File $GitHubOutput -Append
Write-Output "::endgroup::"

Write-Output "::group::Get Options"
$Options = Get-Content $RepoName/ci/options.json | ConvertFrom-Json
Write-Output $Options

$RequiredOptions = @()
$RunPerformance = $false
foreach ($element in $Options) {
  if ($element.PackageRequirement) {
    $element | Add-Member -Name "Version" -Value $Version -MemberType NoteProperty
    $RequiredOptions += $element
    if ($element.RunPerformance) {
      $RunPerformance = $true
    }
  }
}
if ($RequiredOptions.Count -eq 0) {
  # As there are no prebuild steps, add an empty one to ensure the YAML is still valid.
  $RequiredOptions += @{
    "Name" = "No Prebuild"
    "PackageRequirement" = $False
    "Image" = $BuildPlatform
  }
}
$RequiredOptions = $RequiredOptions | ConvertTo-Json -AsArray
$RequiredOptions = $RequiredOptions -replace "`r?`n", ""
Write-Host $RequiredOptions
Write-Output options=$RequiredOptions | Out-File $GitHubOutput -Append
if ($RunPerformance) { Write-Output runperformance=true | Out-File $GitHubOutput -Append }
Write-Output $RequiredOptions
Write-Output "::endgroup::"

exit # Ignore $LASTEXITCODE here
