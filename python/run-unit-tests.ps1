param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string[]]$Packages
)

$commonTestResults = New-Item -ItemType directory -Path $RepoName/test-results/unit -Force
$repoPath = Get-Item -Path $RepoName
$testsFailed = $false

Push-Location $RepoName
try {
    foreach ($package in $Packages) {
        Write-Output "Testing $package"
        Push-Location $package
        try {
            Write-Output "Running tests in '$pwd'"
            # coverage run -m xmlrunner discover -s tests -p 'test*.py' -o $commonTestResults || $($testsFailed = $true)
            $coverageOutputFile = Join-Path -Path $commonTestResults -ChildPath "$package.xml"
            $toxEnv = $env:GITHUB_JOB -ilike "build*test" ? "py" : "pre-publish"
            python -m tox -e $toxEnv -- --junit-xml=$coverageOutputFile || $($testsFailed = $true)
            Move-Item -Path .coverage -Destination $repoPath/.coverage.$package || $(throw "failed to move coverage report")
        } finally {
            Pop-Location
        }
    }
    coverage combine || $(throw "coverage combine failed")
    coverage xml || $(throw "coverage xml failed")
} finally {
    Pop-Location
}

exit $testsFailed ? 1 : 0
