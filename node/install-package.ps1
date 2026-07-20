param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

npm install --prefix $RepoName package/*.tgz
