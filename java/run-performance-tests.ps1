param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name,
    [string]$TestName
)

$ok = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Testing $Name"
    mvn test --batch-mode --no-transfer-progress -Dtest="*$TestName*" || $($ok = $false)

    # Copy the test results into the test-results folder
    $destDir = New-Item -ItemType directory -Force -Path "test-results/performance"
    Get-ChildItem -Directory -Depth 1 -Filter 'pom.xml' | ForEach-Object {
        $targetDir = "$($_.DirectoryName)/target/surefire-reports"
        if (Test-Path $targetDir) {
            Copy-Item -Filter "*$TestName*" $targetDir/* $destDir
        }
    }
    Copy-Item -Recurse $destDir "test-results/performance-summary"
} finally {
    Write-Host "Leaving '$RepoPath'"
    Pop-Location
}

exit $ok ? 0 : 1
