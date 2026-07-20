param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Installing dependencies"
npm --prefix $RepoName install

Write-Host "Linting"
npm --prefix $RepoName run lint
