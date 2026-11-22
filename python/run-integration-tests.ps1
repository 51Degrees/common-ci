param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string[]]$Packages,
    [Parameter(Mandatory=$true)]
    [hashtable]$Keys
)

$env:resource_key = $Keys.TestResourceKey
$env:license_key = $Keys.DeviceDetection

$commonTestResults = New-Item -ItemType directory -Path $RepoName/test-results/integration -Force
$repoPath = Get-Item -Path $RepoName
$testsFailed = $false

# used only in nightly-publish-main workflow
if ($env:GITHUB_JOB -eq "Test") {
    # this part generates a requirements file that is used by the integration
    # tests to install built packages from the local filesystem

    $packagesDir = Get-Item -Path package

    # get all the tar.gz files in the package directory
    $tarFiles = Get-ChildItem -Path $packagesDir -Filter *.tar.gz

    $preRequirementsFile = Join-Path -Path $packagesDir -ChildPath "pre-publish-requirements.txt"

    # if doesn't exist, create a requirements file
    if (!(Test-Path $preRequirementsFile)) {
        New-Item -Path $preRequirementsFile -ItemType "file"
    }

    $tarFiles | ForEach-Object {
        # get the absolute path to the package and append it to the requirements file
        $_.FullName | Out-File -Append -FilePath $preRequirementsFile
    }
}

Push-Location $RepoName
try {
    foreach ($package in $Packages) {
        Write-Output "Testing $package"
        Push-Location $package
        try {
            Write-Output "Running tests in '$pwd'"
            # coverage run -m xmlrunner discover -s tests -p 'test*.py' -o $commonTestResults || $($testsFailed = $true)
            $packageName = Split-Path -Path $pwd -Leaf # Required for location-python, which uses . as package path
            $coverageOutputFile = Join-Path -Path $commonTestResults -ChildPath "$packageName.xml"
            $toxEnv = $env:GITHUB_JOB -ilike "build*test" ? "py" : "pre-publish"
            python -m tox -e $toxEnv -- --junit-xml=$coverageOutputFile || $($testsFailed = $true)
            Move-Item -Path .coverage -Destination $repoPath/.coverage.$packageName || $(throw "failed to move coverage report")
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
