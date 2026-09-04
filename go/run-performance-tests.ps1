<#
.SYNOPSIS
Runs a Go performance example and publishes the results JSON it emits.

.DESCRIPTION
The example writes its own results JSON in the shared schema (see
steps/publish-performance-results.ps1), so this adapter only runs it and hands
the file over. It does not parse the example's console output.
#>
param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$Name,
    # The package path of the performance example within the examples repository.
    [Parameter(Mandatory)][string]$Example,
    [Parameter(Mandatory)][string]$ExamplesRepo,
    # The Go module path of the repository under test. The examples are pinned to
    # this checkout rather than the published module so the figures track the
    # code being tested.
    [string]$ModulePath = "github.com/$OrgName/$RepoName/v4",
    [string]$Branch = "main"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$rootDir = $PWD
$repoPath = Join-Path $rootDir $RepoName
# An absolute path, because the example runs with the examples repository as its
# working directory.
$resultsFile = Join-Path $rootDir "results_$Name.json"

Write-Host "Cloning examples..."
git clone --branch $Branch --depth 1 "https://github.com/$OrgName/$ExamplesRepo.git"

Push-Location $ExamplesRepo
try {
    Write-Host "Using local $RepoName version"
    go mod edit -replace "$ModulePath=$repoPath"

    Write-Host "Running performance test..."
    go run $Example -json-output $resultsFile
} finally {
    Pop-Location
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
