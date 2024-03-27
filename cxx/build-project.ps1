
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir = ".",
    [string]$RepoName,
    [string]$Name,
    [string]$Arch = "x64",
    [string]$Configuration = "Release",
    [string]$BuildMethod = "cmake",
    [string]$BuildDir = "build",
    [string]$ExtraArgs
)

if ($BuildMethod -eq "cmake") {

    $RepoPath = [IO.Path]::Combine($pwd, $RepoName, $ProjectDir, $BuildDir)
    mkdir $RepoPath

    Write-Output "Entering '$RepoPath'"
    Push-Location $RepoPath

    if($IsWindows -and $Arch -eq "x86"){
        $ExtraArgs += ' -A win32'
    }

    try {
    
        Write-Output "Building '$Name'"
        
        Invoke-Expression "cmake .. -DCMAKE_BUILD_TYPE=$Configuration $ExtraArgs"
    
        cmake --build . --config $Configuration  
    
    }
    finally {
    
        Write-Output "Leaving '$RepoPath'"
        Pop-Location
    
    }
}
elseif ($BuildMethod -eq "msbuild") {

    $RepoPath = [IO.Path]::Combine($pwd, $RepoName, $ProjectDir)

    Write-Output "Entering '$RepoPath'"
    Push-Location $RepoPath
    
    try {

        nuget restore
        msbuild /p:Configuration=$Configuration /p:Platform=$Arch /p:OutDir=$RepoPath\$BuildDir

    }
    finally {

        Write-Output "Leaving '$RepoPath'"
        Pop-Location

    }
}
else {

    Write-Error "The build method '$BuildMethod' is not supported."

}

exit $LASTEXITCODE
