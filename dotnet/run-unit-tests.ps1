[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [string]$Configuration = "Release",
    [string]$Arch = "x64",
    [string]$BuildMethod="dotnet",
    [string]$BlameHangTimeout="5m",
    [string]$DirNameFormatForDotnet = "*bin*",
    [string]$DirNameFormatForNotDotnet = "*\bin\*",
    [string]$Filter,
    [string]$OutputFolder = "unit",
    [switch]$KeepPlatformArgs
)

$SkipPlatformArgs = (-not $KeepPlatformArgs) -and (($Arch -eq "Any CPU") -or ($Filter.Contains("dll")))
Write-Output "SkipPlatformArgs = $SkipPlatformArgs"

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$TestResultPath = [IO.Path]::Combine($RepoPath, "test-results", $OutputFolder, $Name)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

function Write-VerboseDebug {
    param([string]$Message)

    if ($VerbosePreference -eq 'Continue') {
        Write-Debug $Message
    }
}


try {
    $script:ok = $true
    $verbose = $IsMacOS ? '--verbosity', 'd' : $null # macOS debugging

    $skipPattern = "*performance*"
    Write-Output "Testing '$Name'"
    Write-Output "BuildMethod: $BuildMethod"
    Write-Output "Initial ok value: $($script:ok)"
    Write-Output "Initial LASTEXITCODE: $LASTEXITCODE"

    # Reset LASTEXITCODE to ensure clean state
    $LASTEXITCODE = 0
    if ($BuildMethod -eq "dotnet"){
        Write-Output "[dotnet] => Looking for '$Filter' in directories like '$DirNameFormatForDotnet'"

        $PlatformParams = $SkipPlatformArgs ? @() : @("-p:Platform=$Arch")
        $testRunsettings = [IO.Path]::Exists('test.runsettings') ? @('--settings', 'test.runsettings') : @()

        foreach ($NextFile in (Get-ChildItem -Path $RepoPath -Recurse -File)) {
            $NextDirName = $NextFile.DirectoryName
            $NextFileName = $NextFile.Name
            Write-VerboseDebug "[$NextDirName]/[$NextFileName]"
            if ($NextDirName -notlike $DirNameFormatForDotnet) {
                Write-VerboseDebug "- $NextDirName not matched $DirNameFormatForDotnet"
            } elseif ($NextFileName -like $skipPattern) {
                Write-VerboseDebug "- $NextFileName matched $skipPattern"
            } elseif ($NextFileName -notmatch "$Filter") {
                Write-VerboseDebug "- $NextFileName not matched $Filter"
            } else {
                Write-Output "Testing Assembly: '$NextFile'"
                $TestArgs = @(
                    $NextFile.FullName
                    "--no-build"
                    "--configuration", $Configuration
                    $PlatformParams
                    $testRunsettings
                    "--results-directory", $TestResultPath
                    "--blame-crash", "--blame-hang-timeout", $BlameHangTimeout
                    "-l", "trx"
                    $verbose
                )
                Write-Debug (
                    $TestArgs
                    | ForEach-Object { [PSCustomObject]@{ Index = $i++; Value = $_ } }
                    | Out-String
                )
                dotnet test @TestArgs
                Write-Output "dotnet test LastExitCode=$LASTEXITCODE"
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "Setting ok=false due to dotnet test exit code $LASTEXITCODE for $NextFile"
                    $script:ok = $false
                }
            }
        }
    } else {
        Write-Output "[$BuildMethod] ~> Looking for '$Filter' in directories like '$DirNameFormatForNotDotnet'"
        $PlatformParams = $SkipPlatformArgs ? @() : @("/Platform:$Arch")
        foreach ($NextFile in (Get-ChildItem -Path $RepoPath -Recurse -File)) {
            $NextDirName = $NextFile.DirectoryName
            $NextFileName = $NextFile.Name
            Write-VerboseDebug "[$NextDirName]/[$NextFileName]"
            if ($NextDirName -notlike $DirNameFormatForNotDotnet) {
                Write-VerboseDebug "- $NextDirName not matched $DirNameFormatForNotDotnet"
            } elseif ($NextFileName -like $skipPattern) {
                Write-VerboseDebug "- $NextFileName matched $skipPattern"
            } elseif ($NextFileName -notmatch "$Filter") {
                Write-VerboseDebug "- $NextFileName not matched $Filter"
            } else {
                Write-Output "Testing Assembly: '$NextFile'"
                & vstest.console.exe $NextFile.FullName `
                    @PlatformParams `
                    /Logger:trx `
                    /ResultsDirectory:$TestResultPath
                Write-Output "vstest.console LastExitCode=$LASTEXITCODE"
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "Setting ok=false due to vstest.console exit code $LASTEXITCODE for $NextFile"
                    $script:ok = $false
                }
            }
        }
    }

    Write-Output "Final test result: ok = $($script:ok)"
    if (!$script:ok) {
        Write-Error "Tests failed"
    }
} finally {
    Write-Output "Leaving '$RepoPath'"
    Pop-Location
}
