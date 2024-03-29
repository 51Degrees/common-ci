
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$Configuration = "Release",
    [string]$Arch = "x64"
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName, $ProjectDir, "build")

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {

    Write-Output "Testing $($Options.Name)"

    ctest -C $Configuration -T test --no-compress-output --output-junit "../test-results/performance/$Name.xml" --tests-regex .*Perf.*
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
