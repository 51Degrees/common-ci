param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [bool]$Force,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if ($DryRun) {
    Write-Output "Dry run - not pushing"
} else {
    git -C $RepoName push ($Force ? '--force-with-lease' : $null) origin HEAD
}
