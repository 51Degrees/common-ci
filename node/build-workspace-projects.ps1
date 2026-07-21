param ([Parameter(Mandatory)][string]$RepoName)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Push-Location $RepoName
try {
    Write-Host "Installing dependencies"
    npm install

    Write-Host "Linting"
    npm run lint
} finally { Pop-Location }
