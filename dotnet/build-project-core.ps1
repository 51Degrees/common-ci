
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [string]$Configuration = "Release",
    [string]$Arch = "x64"
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    Write-Output "Building '$Name'"
    dotnet build $ProjectDir -c $Configuration /p:Platform=$Arch /p:BuiltOnCI=true || Write-Error "build failed"
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}
