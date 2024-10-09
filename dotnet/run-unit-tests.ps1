param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [string]$Configuration = "Release",
    [string]$Arch = "x64",
    [string]$BuildMethod="dotnet",
    [string]$DirNameFormatForDotnet = "*bin*",
    [string]$DirNameFormatForNotDotnet = "*\bin\*",
    [string]$Filter,
    [string]$OutputFolder = "unit"
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$TestResultPath = [IO.Path]::Combine($RepoPath, "test-results", $OutputFolder, $Name)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    $ok = $true

    $skipPattern = "*performance*"
    Write-Output "Testing '$Name'"
    if ($BuildMethod -eq "dotnet"){
        Write-Output "[dotnet] => Looking for '$Filter' in directories like '$DirNameFormatForDotnet'"
        Get-ChildItem -Path $RepoPath -Recurse -File | ForEach-Object {
            if (($_.DirectoryName -like $DirNameFormatForDotnet -and $_.Name -notlike $skipPattern) -and ($_.Name -match "$Filter")) {
                Write-Output "Testing Assembly: '$_'"
                dotnet test $_.FullName --results-directory $TestResultPath --blame-crash -l "trx" || $($script:ok = $false)
            }
        }
    } else {
        Write-Output "[$BuildMethod] ~> Looking for '$Filter' in directories like '$DirNameFormatForNotDotnet'"
        Get-ChildItem -Path $RepoPath -Recurse -File | ForEach-Object {
            if (($_.DirectoryName -like $DirNameFormatForNotDotnet -and $_.Name -notlike $skipPattern) -and ($_.Name -match "$Filter")) {
                Write-Output "Testing Assembly: '$_'"
                & vstest.console.exe $_.FullName /Logger:trx /ResultsDirectory:$TestResultPath || $($script:ok = $false)
            }
        }
    }

    if (!$ok) {
        Write-Error "Tests failed"
    }
} finally {
    Write-Output "Leaving '$RepoPath'"
    Pop-Location
}
