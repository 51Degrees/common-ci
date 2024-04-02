
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$Branch = "",
    [string]$GitHubUser = "",
    [string]$GitHubEmail = "",
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [bool]$DryRun = $False
)

. ./constants.ps1

if ($GitHubUser -eq "") {
  $GitHubUser = $DefaultGitUser
}
if ($GitHubEmail -eq "") {
  $GitHubEmail = $DefaultGitEmail
}

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $Branch
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Get Next Package Version"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "get-next-package-version.ps1" -Options @{VariableName = "Version"} -DryRun $DryRun
Write-Output version=$Version
$IsValid = [bool]([regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)(-SNAPSHOT)?$')) 
if ($IsValid -eq $False) {
  Write-Error "The package version was not valid: '$Version'"
  exit 1
}
Write-Output version=$Version | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Output "::group::Package Update Required"
try {
    ./steps/package-update-required.ps1 -RepoName $RepoName -Version $Version
} finally {
    if ($LASTEXITCODE -eq 0) {
        Write-Output update_required=true | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
    } else {
      Write-Output update_required=false | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
      # Set a zero exit code as we don't want to fail just because an update is not required.
      $LASTEXITCODE = 0
    }
}
Write-Output "::endgroup::"

Write-Output "::group::Get Options"
$OptionsFile = [IO.Path]::Combine($pwd, $RepoName, "ci", "options.json")

$Options = Get-Content $OptionsFile | ConvertFrom-Json

Write-Output $Options

$RequiredOptions = @()
foreach ($element in $Options)
{
  if ($element.PackageRequirement) {
    $element | Add-Member -Name "Version" -Value $Version -MemberType NoteProperty
    $RequiredOptions += $element
  }
}
if ($RequiredOptions.Count -eq 0) {
  # As there are no prebuild steps, add an empty one to ensure the YAML is still valid.
  $RequiredOptions += @{
    "Name" = "No Prebuild"
    "PackageRequirement" = $False
    "Image" = "ubuntu-latest"
  }
}
$RequiredOptions = $RequiredOptions | ConvertTo-Json -AsArray
$RequiredOptions = $RequiredOptions -replace "`r`n", "" -replace "`n", ""
Write-Host $RequiredOptions
Write-Output options=$RequiredOptions | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
Write-Output $RequiredOptions
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
