
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$Source = "https://api.nuget.org/v3/index.json"
)

$PackagePath = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$PackagePath'"
Push-Location $PackagePath

try {

    Write-Output "Releasing package for '$Name'"
    
    dotnet nuget push "*.nupkg" --source $Source --api-key $ApiKey

}
finally {

    Write-Output "Leaving '$PackagePath'"
    Pop-Location

}

exit $LASTEXITCODE
