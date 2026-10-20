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
    mvn surefire:test --batch-mode --no-transfer-progress -DfailIfNoTests=false $ExtraArgs || $($ok = $false)

    # Copy the test results into the test-results folder
    $destDir = New-Item -ItemType directory -Force -Path "test-results/unit"
    Get-ChildItem -File -Depth 1 -Filter 'pom.xml' | ForEach-Object {
        $targetDir = "$($_.DirectoryName)/target/surefire-reports"
        if (Test-Path $targetDir) {
            Copy-Item -Exclude "*ExampleTests*" $targetDir/* $destDir
        }
    }
} finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}

# A forked JVM that dies leaves why it died only on the runner, so log it. This
# does not change the outcome.
if ($ok -eq $false) {
    & "$PSScriptRoot/collect-jvm-crash-evidence.ps1" -RepoName $RepoName
}

exit $ok ? 0 : 1
