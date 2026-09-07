param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$Name,
    # The package path of the performance example, relative to the directory it
    # is run from: the examples repository, or the repository itself.
    [Parameter(Mandatory)][string]$Example,
    # The examples repository to clone. Leave unset when the examples live in
    # the repository under test.
    [string]$ExamplesRepo,
    # The examples are pinned to this checkout, not the published module.
    [string]$ModulePath = "github.com/$OrgName/$RepoName/v4",
    [string]$Branch = "main"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$rootDir = $PWD
$repoPath = Join-Path $rootDir $RepoName
# Absolute, because the example runs from its own directory.
$resultsFile = Join-Path $rootDir "results_$Name.json"
Remove-Item -Path $resultsFile -Force -ErrorAction SilentlyContinue

if ($ExamplesRepo) {
    Write-Host "Cloning examples..."
    git clone --branch $Branch --depth 1 "https://github.com/$OrgName/$ExamplesRepo.git"
    $exampleDir = Join-Path $rootDir $ExamplesRepo
} else {
    $exampleDir = $repoPath
}

Push-Location $exampleDir
try {
    if ($ExamplesRepo) {
        Write-Host "Using local $RepoName version"
        go mod edit -replace "$ModulePath=$repoPath"
    }

    Write-Host "Running performance test..."
    go run $Example -json-output $resultsFile
} finally {
    Pop-Location
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
