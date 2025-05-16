param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name,
    [string[]]$ExtraArgs
)

$ok = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Testing '$Name'"
    mvn surefire:test --batch-mode --no-transfer-progress $ExtraArgs || $($ok = $false)

    # Copy the test results into the test-results folder
    $destDir = New-Item -ItemType directory -Force -Path "test-results/unit"
    Get-ChildItem -Directory -Depth 1 -Filter 'pom.xml' | ForEach-Object {
        $targetDir = "$($_.DirectoryName)/target/surefire-reports"
        if (Test-Path $targetDir) {
            Copy-Item -Exclude "*ExampleTests*" $targetDir/* $destDir
        }
    }
} finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}

exit $ok ? 0 : 1
