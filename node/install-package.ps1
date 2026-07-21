param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $RepoName
try {
    Get-ChildItem ../package/*.tgz | ForEach-Object { npm install $_ }
} finally { Pop-Location }
