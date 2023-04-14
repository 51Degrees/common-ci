
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName, $ProjectDir)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    Write-Output "Testing $Name"
    mvn test -Dtest=*Integration* -DfailIfNoTests=false 

    # Copy the test results into the test-results folder
    Get-ChildItem -Path . -Directory -Depth 1 | 
    Where-Object { Test-Path "$($_.FullName)\pom.xml" } | 
    ForEach-Object { 
        $targetDir = "$($_.FullName)\target\surefire-reports"
        $destDir = ".\test-results\integration"
        if(!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir }
        if(Test-Path $targetDir) { 
            Copy-Item -Path "$targetDir\*" -Destination $destDir -Recurse 
        }
    }
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE