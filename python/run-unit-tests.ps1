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
            # Named by the folder rather than by $package, because a monorepo
            # passes the package as a path, and a '/' in these names would put
            # the results in a folder that does not exist. run-integration-tests.ps1
            # does the same.
            $packageName = Split-Path -Path $pwd -Leaf
            $coverageOutputFile = Join-Path -Path $commonTestResults -ChildPath "$packageName.xml"
            $toxEnv = $env:GITHUB_JOB -ilike "build*test" ? "py" : "pre-publish"
            python -m tox -e $toxEnv -- --junit-xml=$coverageOutputFile || $($testsFailed = $true)
            Move-Item -Path .coverage -Destination $repoPath/.coverage.$packageName ||
                $(throw "failed to move coverage report")
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
