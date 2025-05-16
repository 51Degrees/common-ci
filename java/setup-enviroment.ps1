param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$JavaSDKEnvVar
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Setting up $JavaSDKEnvVar"

    # Set the JAVA_HOME environment variable
    $env:JAVA_HOME = $JavaSDKEnvVar

    # Add the Java binary directory to the system PATH
    $env:PATH = "$env:JAVA_HOME/bin$([IO.Path]::PathSeparator)$env:PATH"
    
    # Write the value of the environment variable to the GITHUB_ENV file,
    # which makes the variable available to all subsequent steps in the job.
    Write-Output "JAVA_HOME=$env:JAVA_HOME" | Out-File -Encoding utf8 -FilePath $env:GITHUB_ENV -Append

    # Output java version used
    java -version
} finally {
    Write-Host "Leaving '$RepoPath'"
    Pop-Location
}
