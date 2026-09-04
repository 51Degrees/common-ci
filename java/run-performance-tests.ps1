<#
.SYNOPSIS
Runs a Java performance test and publishes the results JSON it emits.

.DESCRIPTION
The performance test writes its own results JSON in the shared schema (see
steps/publish-performance-results.ps1) to the path given by the
fiftyone.performance.json system property, so this adapter only runs it and
hands the file over. It does not parse the test's console output.

The surefire reports are still copied to test-results/performance, which is the
unit-test result feed and a separate concern from the performance figure.
#>
param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$TestName
)

$ok = $true
$rootDir = $PWD
# An absolute path, because Maven runs each module with its own working directory.
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
    # Report the test failure rather than letting the publish step fail with a
    # missing-results-file error, which would hide the real cause.
    Write-Warning "Performance tests failed, so the results are not published"
    exit 1
}

& "$rootDir/steps/publish-performance-results.ps1" -SourceFile $resultsFile -Name $Name -RepoName $RepoName
