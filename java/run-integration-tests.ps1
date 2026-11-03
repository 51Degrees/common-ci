param(
    [Parameter(Mandatory)][string]$RepoName,
    [string]$Name
)

$ok = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Testing $Name"
    mvn test --batch-mode --no-transfer-progress -DfailIfNoTests=false -Dtest=ExampleTests || $($ok = $false)

    # Copy the test results into the test-results folder. Modules can be any
    # number of folders down, as in a repository of several package trees.
    # A pom below target or node_modules is a copy, not a module.
    $destDir = New-Item -ItemType directory -Force -Path "test-results/integration"
    Get-ChildItem -File -Recurse -Filter 'pom.xml' |
        Where-Object { $_.FullName -notmatch '[\\/](target|node_modules)[\\/]' } |
        ForEach-Object {
            $targetDir = "$($_.DirectoryName)/target/surefire-reports"
            if (Test-Path $targetDir) {
                Copy-Item -Filter "*ExampleTests*" $targetDir/* $destDir
            }
        }
} finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}

exit $ok ? 0 : 1
