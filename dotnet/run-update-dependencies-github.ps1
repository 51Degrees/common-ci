param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$ProjectDir = ".",
    [string]$Name
)

$FetchVersions = {
    param($PackageName)
    gh api `
       -H "Accept: application/vnd.github+json" `
       -H "X-GitHub-Api-Version: 2022-11-28" `
       /orgs/$OrgName/packages/nuget/$PackageName/versions | ConvertFrom-Json | ForEach-Object -Process { @{"Version" = $_.name }}
}

./dotnet/run-update-dependencies.ps1 -RepoName $RepoName -ProjectDir $ProjectDir -Name $Name -FetchVersions $FetchVersions
