
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$TestName
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName, $ProjectDir)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

$ok = $true

try {

    Write-Output "Testing $Name"
    mvn -B test -Dtest="*$TestName*" -DfailIfNoTests=false || $($ok = $false) 
    # Copy the test results into the test-results folder
    Get-ChildItem -Path . -Directory -Depth 1 | 
    Where-Object { Test-Path "$($_.FullName)\pom.xml" } | 
    ForEach-Object { 
        $targetDir = "$($_.FullName)\target\surefire-reports"
        $destDir = "..\$RepoName\test-results\performance"
        $destDirSummary = "..\$RepoName\test-results\performance-summary"

        if(!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir }
        if(Test-Path $targetDir) {
            Get-ChildItem -Path $targetDir | 
            Where-Object { $_.Name -like "*$TestName*" } |
            ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $destDir
            }
        }
    }

    Copy-Item -Path $destDir -Destination $destDirSummary -Recurse

}

finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $ok ? 0 : 1
