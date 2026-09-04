<#
.SYNOPSIS
Runs the C/C++ performance tests and publishes the results JSON the performance
example emits.

.DESCRIPTION
The performance example writes its own results JSON in the shared schema (see
steps/publish-performance-results.ps1), so this adapter only runs it and hands
the file over. It does not parse the example's console output.
#>
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
