[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$Filter = "*.csproj",
    [scriptblock]$FetchVersions = { param($PackageName) Find-Package -Name $PackageName -AllVersions -Source https://api.nuget.org/v3/index.json -ErrorAction SilentlyContinue }
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    dotnet restore $ProjectDir

    foreach ($ProjectFile in $(Get-ChildItem -Path $pwd -Filter $Filter -Recurse -ErrorAction SilentlyContinue -Force)) {
        Write-Output "========= ========= ========="
        Write-Output $ProjectFile.FullName

        $ProjectPackagesOutdatedRaw = (dotnet list $ProjectFile.FullName package --format json --outdated --highest-patch --include-prerelease)
        Write-Debug "----- RAW OUTPUT START -----"
        Write-Debug ($ProjectPackagesOutdatedRaw -Join "`n")
        Write-Debug "----- RAW OUTPUT END -----"
        if ($ProjectPackagesOutdatedRaw[0][0] -ne '{') {
            Write-Warning "^ NOT A VALID JSON -- (continue)"
            continue
        }

        Write-Debug "OUTDATED PACKAGES:"
        $ProjectPackagesOutdated = (ConvertFrom-Json -InputObject (-Join $ProjectPackagesOutdatedRaw))
        Write-Debug (ConvertTo-Json -InputObject $ProjectPackagesOutdated -Depth 6)

        $RequestedPackages = @{}
        foreach ($ProjectDic in $ProjectPackagesOutdated.projects) {
            Write-Debug "--------"
            Write-Debug $ProjectDic.path
            if ($null -eq $ProjectDic.frameworks) {
                continue
            }
            if (!$RequestedPackages.ContainsKey($ProjectDic.path)) {
                $RequestedPackages[$ProjectDic.path] = @{}
            }
            $ProjectFileUpdates = $RequestedPackages[$ProjectDic.path]
            foreach ($FrameworkDic in $ProjectDic.frameworks) {
                foreach ($PackageDic in $FrameworkDic.topLevelPackages) {
                    if (!$ProjectFileUpdates.ContainsKey($PackageDic.id)) {
                        $ProjectFileUpdates[$PackageDic.id] = @{}
                    }
                    $PackageUpdates = $ProjectFileUpdates[$PackageDic.id]
                    $PackageUpdates[$FrameworkDic.framework] = [PSCustomObject]@{
                        Requested = $PackageDic.requestedVersion
                        Latest = $PackageDic.latestVersion
                    }
                }
            }
        }
        if ($RequestedPackages.Count -eq 0) {
            Write-Output "✅ NO UPDATES"
            continue
        }
        Write-Output "NECESSARY UPDATES:"
        Write-Output (ConvertTo-Json -InputObject $RequestedPackages -Depth 4)
        Write-Debug "FULL PACKAGES:"
        $ProjectPackagesFull = (dotnet list $ProjectFile.FullName package --format json | ConvertFrom-Json)
        Write-Debug (ConvertTo-Json -InputObject $ProjectPackagesFull -Depth 6)

        foreach ($ProjectDic in $ProjectPackagesFull.projects) {
            if (!$RequestedPackages.ContainsKey($ProjectDic.path)) {
                continue
            }
            $ProjectFileUpdates = $RequestedPackages[$ProjectDic.path]
            foreach ($FrameworkDic in $ProjectDic.frameworks) {
                foreach ($PackageDic in $FrameworkDic.topLevelPackages) {
                    if (!$ProjectFileUpdates.ContainsKey($PackageDic.id)) {
                        continue
                    }
                    $PackageUpdates = $ProjectFileUpdates[$PackageDic.id]
                    if ($PackageUpdates.ContainsKey($FrameworkDic.framework)) {
                        continue
                    }
                    # Ignore version ranges like [1.0,1.0)
                    if ($PackageDic.requestedVersion.Contains('[') -eq $false -and
                        $PackageDic.requestedVersion.Contains(']') -eq $false -and
                        $PackageDic.requestedVersion.Contains('(') -eq $false -and
                        $PackageDic.requestedVersion.Contains(')') -eq $false) 
                    {
                        $PackageUpdates[$FrameworkDic.framework] = [PSCustomObject]@{
                            Requested = $PackageDic.requestedVersion
                            Latest = $PackageDic.requestedVersion
                        }
                    }
                }
            }
        }
        Write-Output "AMENDED UPDATES:"
        Write-Output (ConvertTo-Json -InputObject $RequestedPackages -Depth 4)

        foreach ($ProjectFilePath in $RequestedPackages.Keys) {
            Write-Output "===== ===== ====="
            Write-Output "Operating on: $ProjectFilePath"
            $ProjectFileUpdates = $RequestedPackages[$ProjectFilePath]
            foreach ($PackageId in $ProjectFileUpdates.keys) {
                Write-Output "----- -----"
                Write-Output "REMOVING $PackageId"
                dotnet remove $ProjectFilePath package $PackageId
                $PackageVersionUpdates = $ProjectFileUpdates[$PackageId]
                foreach ($NextFramework in $PackageVersionUpdates.keys) {
                    $NextPackageUpdate = $PackageVersionUpdates[$NextFramework]
                    Write-Output "----- -----"
                    Write-Output "REINSTALLING $PackageId --- v.$($NextPackageUpdate.Latest) for [$NextFramework]"
                    dotnet add $ProjectFilePath package $PackageId -v $NextPackageUpdate.Latest -f $NextFramework
                }
            }
        }
    }
    Write-Output "========= ========= ========="
}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
