param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$VariableName = "GitVersion",
    [string]$GitVersionConfigPath
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Entering $RepoName"
Push-Location $RepoName
try {
    Write-Output "Installing gitversion"
    dotnet tool install --global GitVersion.Tool --version 6.*

    $GitVersionOutput = dotnet-gitversion ($GitVersionConfigPath ? '/config', $GitVersionConfigPath : $null)

    Write-Output "Setting $VariableName to:"
    Write-Output $GitVersionOutput
    Set-Variable -Scope 1 -Name $VariableName -Value $($GitVersionOutput | ConvertFrom-Json)

} finally {
    Write-Output "Leaving $RepoName"
    Pop-Location
}

