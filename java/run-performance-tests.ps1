param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$TestName
)

$ok = $true
$rootDir = $PWD
# Absolute, because Maven runs each module from its own directory.
$resultsFile = Join-Path $rootDir "results_$Name.json"
Remove-Item -Path $resultsFile -Force -ErrorAction SilentlyContinue

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Testing $Name"
    mvn test --batch-mode --no-transfer-progress -DfailIfNoTests=false -Dtest="*$TestName*" "-Dfiftyone.performance.json=$resultsFile" || $($ok = $false)

    # Copy the test results into the test-results folder
    $destDir = New-Item -ItemType directory -Force -Path "test-results/performance"
    Get-ChildItem -File -Depth 1 -Filter 'pom.xml' | ForEach-Object {
        $targetDir = "$($_.DirectoryName)/target/surefire-reports"
        if (Test-Path $targetDir) {
            Copy-Item -Filter "*$TestName*" $targetDir/* $destDir
        }
    }
} finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}

if (-not $ok) {
    # Stop here, so a test failure isn't reported as a missing results file.
    Write-Warning "Performance tests failed, so the results are not published"
    exit 1
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
