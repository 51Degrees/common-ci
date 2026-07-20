param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

npm --prefix $RepoName install
