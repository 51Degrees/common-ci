param (
    [Parameter(Mandatory)][string]$RepoName,
    [string]$VariableName = "Version"
)
$ErrorActionPreference = "Stop"

Set-Variable -Scope Global -Name $VariableName -Value "v$(./steps/get-next-package-version.ps1 -RepoName $RepoName)"
