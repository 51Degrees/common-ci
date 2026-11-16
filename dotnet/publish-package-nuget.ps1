
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$Source = "https://api.nuget.org/v3/index.json",
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
# dotnet's exit codes are checked by hand, so that every package is verified
# and all the failures are reported together.
$PSNativeCommandUseErrorActionPreference = $false

$PackagePath = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$PackagePath'"
Push-Location $PackagePath

try {

    # nuget.org accepts a package whose signature no longer matches it, says
    # it was pushed, and then drops it in its own checks. So nothing is pushed
    # unless every package verifies. Other feeds take unsigned packages, so
    # only nuget.org is checked. A dry run checks too, so that it fails where
    # the real publish would. dotnet nuget verify works on Windows and Linux,
    # not on macOS.
    if ($Source -match "^https://api\.nuget\.org/") {
        $Packages = @(Get-ChildItem -Path $PackagePath -Filter "*.nupkg" -File)

        if ($Packages.Count -eq 0) {
            throw "No packages were found in '$PackagePath'"
        }

        Write-Output "Verifying $($Packages.Count) package(s) before pushing"

        $Failures = @()
        foreach ($Package in $Packages) {
            Write-Output "Verifying '$($Package.Name)'"
            dotnet nuget verify $Package.FullName
            if ($LASTEXITCODE -ne 0) {
                $Failures += $Package.Name
            }
        }

        if ($Failures.Count -gt 0) {
            throw ("Package verification failed for " +
                "$($Failures -join ', '). Nothing has been pushed.")
        }

        Write-Output "All packages verified"
    }

    Write-Output "Releasing package for '$Name'"

    if ($DryRun) {
        Write-Output "Dry run - not pushing $((Get-ChildItem *.nupkg).Name -join ', ') to '$Source'"
    } else {
        dotnet nuget push "*.nupkg" --source $Source --api-key $ApiKey --skip-duplicate
    }

}
finally {

    Write-Output "Leaving '$PackagePath'"
    Pop-Location

}

exit $LASTEXITCODE
