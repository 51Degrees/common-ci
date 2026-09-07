param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$Configuration = "Release",
    [string]$Arch = "x64"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$BuildPath = "$PWD/$RepoName/$ProjectDir/build"

Write-Output "Entering '$BuildPath'"
Push-Location $BuildPath
try {
    Write-Output "Testing $Name"

    ctest -C $Configuration -T test --no-compress-output --output-junit "../test-results/performance/$Name.xml" --tests-regex .*Perf.*

} finally {
    Write-Output "Leaving '$BuildPath'"
    Pop-Location
}
