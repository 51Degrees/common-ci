param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$ProjectDir = ".",
    [string]$Filter = "*.csproj",
    [string]$Name,
    [switch]$IncludePrerelease
)

$FetchVersions = {
    param($PackageName)
    $Matches = gh api `
       -H "Accept: application/vnd.github+json" `
       -H "X-GitHub-Api-Version: 2022-11-28" `
       /orgs/51degrees/packages?package_type=nuget | convertfrom-json | Where-Object { $_.Name -eq $PackageName }
    if ($Matches.Length -eq 1) {
        return gh api `
           -H "Accept: application/vnd.github+json" `
           -H "X-GitHub-Api-Version: 2022-11-28" `
           /orgs/$OrgName/packages/nuget/$PackageName/versions | ConvertFrom-Json | ForEach-Object -Process { @{"Version" = $_.name }}
    }
    else {
        return @()
    }
}

$UpdateArguments = @{
    RepoName = $RepoName
    ProjectDir = $ProjectDir
    Name = $Name
    Filter = $Filter
    FetchVersions = $FetchVersions
    IncludePrerelease = $IncludePrerelease
}
./dotnet/run-update-dependencies.ps1 @UpdateArguments

exit $LASTEXITCODE
