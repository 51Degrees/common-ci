
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The GitHub feed takes a GitHub token as its key: the automation token, which
# the workflow passes as _51DEGREES_ACCESS_TOKEN.
$Source = "https://nuget.pkg.github.com/$OrgName/index.json"
$PackagePath = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$PackagePath'"
Push-Location $PackagePath

try {
    Write-Output "Releasing package for '$Name'"

    if ($DryRun) {
        Write-Output "Dry run - not pushing $((Get-ChildItem *.nupkg).Name -join ', ') to '$Source'"
    } else {
        if ([string]::IsNullOrWhiteSpace($env:_51DEGREES_ACCESS_TOKEN)) {
            throw "_51DEGREES_ACCESS_TOKEN is not set, so publishing cannot succeed."
        }
        dotnet nuget push "*.nupkg" --source $Source --api-key $env:_51DEGREES_ACCESS_TOKEN --skip-duplicate
    }
}
finally {
    Write-Output "Leaving '$PackagePath'"
    Pop-Location
}