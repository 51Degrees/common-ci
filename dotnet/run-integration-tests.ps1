
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [string]$Configuration = "Release",
    [string]$Arch = "x64",
    [string]$BuildMethod = "msbuild",
    [string]$DirNameFormatForDotnet = "*bin*",
    [string]$DirNameFormatForNotDotnet = "*\bin\*",
    [Parameter(Mandatory=$true)]
    [string]$Filter
)

# DEBUG: print files
Write-Host 'FINDING TESTS!'
find device-detection-dotnet-examples/Tests

./dotnet/run-unit-tests.ps1 -RepoName $RepoName -ProjectDir $ProjectDir -Name $Name -Configuration $Configuration -Arch $Arch -BuildMethod $BuildMethod -Filter $Filter -OutputFolder "integration" -DirNameFormatForDotnet $DirNameFormatForDotnet -DirNameFormatForNotDotnet $DirNameFormatForNotDotnet

