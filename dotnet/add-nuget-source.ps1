
param(
    [Parameter(Mandatory=$true)]
    [string]$Source,
    [Parameter(Mandatory=$true)]
    [string]$UserName,
    [Parameter(Mandatory=$true)]
    [string]$Key
)

Write-Output "Adding NuGet source '$Source'"
dotnet nuget add source $Source --username $UserName --password $Key --store-password-in-clear-text

exit $LASTEXITCODE