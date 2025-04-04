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
    $verbose = $IsMacOS ? '--verbosity', 'd' : $null # macOS debugging

    $skipPattern = "*performance*"
    Write-Output "Testing '$Name'"
    if ($BuildMethod -eq "dotnet"){
        Write-Output "[dotnet] => Looking for '$Filter' in directories like '$DirNameFormatForDotnet'"
        $PlatformParams = ($Arch -eq "Any CPU") ? @() : @("-p:Platform=$Arch")
        Get-ChildItem -Path $RepoPath -Recurse -File | ForEach-Object {
            if (($_.DirectoryName -like $DirNameFormatForDotnet -and $_.Name -notlike $skipPattern) -and ($_.Name -match "$Filter")) {
                Write-Output "Testing Assembly: '$_'"
                dotnet test $_.FullName `
                    --no-build `
                    --configuration $Configuration `
                    @PlatformParams `
                    --results-directory $TestResultPath `
                    --blame-crash --blame-hang-timeout 5m -l "trx" $verbose || $($script:ok = $false)
                Write-Output "dotnet test LastExitCode=$LASTEXITCODE"
            }
        }
    } else {
        Write-Output "[$BuildMethod] ~> Looking for '$Filter' in directories like '$DirNameFormatForNotDotnet'"
        Get-ChildItem -Path $RepoPath -Recurse -File | ForEach-Object {
            $PlatformParams = ($Arch -eq "Any CPU") ? @() : @("/Platform:$Arch")
            if (($_.DirectoryName -like $DirNameFormatForNotDotnet -and $_.Name -notlike $skipPattern) -and ($_.Name -match "$Filter")) {
                Write-Output "Testing Assembly: '$_'"
                & vstest.console.exe $_.FullName `
                    @PlatformParams `
                    /Logger:trx `
                    /ResultsDirectory:$TestResultPath || $($script:ok = $false)
                Write-Output "vstest.console LastExitCode=$LASTEXITCODE"
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
