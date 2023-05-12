
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$VariableName = "Version"
)

./steps/get-next-package-version.ps1 -RepoName $RepoName -VariableName $VariableName

$SemVer = (Get-Variable -Name $VariableName).Value.SemVer
Set-Variable -Name $VariableName -Value $SemVer -Scope Global

exit $LASTEXITCODE
