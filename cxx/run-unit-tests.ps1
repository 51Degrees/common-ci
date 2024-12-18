param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$Configuration = "Release",
    [string]$Arch = "x64",
    [string]$BuildMethod = "cmake",
    [string]$ExcludeRegex = ".*Performance|Integration|Example.*",
    [string[]]$CoverageExcludeDirs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoPath = "$PWD/$RepoName"
$BuildPath = "$RepoPath/$ProjectDir/build"

if ($BuildMethod -eq "cmake") {
    Write-Output "Entering '$BuildPath'"
    Push-Location $BuildPath
    try {
        Write-Output "Testing $Name"

        ctest -C $Configuration -T test --no-compress-output --output-on-failure --output-junit "$RepoPath/test-results/unit/$Name.xml" --exclude-regex $ExcludeRegex

        if (Test-Path CMakeFiles/*-cov.dir) {
            Write-Output "Generating coverage report..."
            $artifacts = New-Item -ItemType directory -Path $RepoPath/artifacts -Force
            python -m gcovr -r $RepoPath -o $artifacts/coverage.html --html-details --html-self-contained `
                --gcov-ignore-parse-errors=negative_hits.warn --exclude '.*\.hpp$' `
                $CoverageExcludeDirs.foreach({'--exclude-directories', "CMakeFiles/$_"}) CMakeFiles || $(throw "gcovr failed")
        }

    } finally {
        Write-Output "Leaving '$BuildPath'"
        Pop-Location
    }

} elseif ($BuildMethod -eq "msbuild") {
    Write-Output "Entering '$BuildPath'"
    Push-Location $BuildPath
    try {
        $TestBinaries = Get-ChildItem -Filter *Test*.exe
        
        foreach ($TestBinary in $TestBinaries) {
            Write-Output $TestBinary.FullName
            Write-Output "Testing $Name-$($TestBinary.Name)"
            & $TestBinary.FullName --gtest_catch_exceptions=1 --gtest_break_on_failure=0 --gtest_output=xml:$RepoPath\test-results\unit\$Name_$($TestBinary.BaseName).xml
        }

    } finally {
        Write-Output "Leaving '$BuildPath'"
        Pop-Location
    }

} else {
    Write-Error "The build method '$BuildMethod' is not supported."
}
