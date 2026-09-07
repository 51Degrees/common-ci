
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release_x64",
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$Source = "https://api.nuget.org/v3/index.json"
)
$ErrorActionPreference = "Stop"
# Exit codes from dotnet are checked here rather than being turned into
# errors automatically, so that every package is checked and all the
# failures can be reported together.
$PSNativeCommandUseErrorActionPreference = $false

$PackagePath = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$PackagePath'"
Push-Location $PackagePath

try {

    # Check every package against its own signature before anything is
    # pushed. A package that was altered after it was signed is still
    # accepted by the push, and is then thrown away by NuGet during the
    # checks NuGet runs afterwards, so the package never appears on the
    # feed whilst the workflow reports success. Catching it here stops a
    # release going out with a package missing.
    #
    # Signature checking is always available on Windows, and on Linux
    # from the .NET 6.0.400 SDK onwards. It is not supported on macOS,
    # so this step will report a failure there rather than a real
    # problem with the package.
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

    Write-Output "Releasing package for '$Name'"

    dotnet nuget push "*.nupkg" --source $Source --api-key $ApiKey --skip-duplicate

}
finally {

    Write-Output "Leaving '$PackagePath'"
    Pop-Location

}

exit $LASTEXITCODE
