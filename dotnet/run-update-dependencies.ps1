param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [scriptblock]$FetchVersions = { param($PackageName) Find-Package -Name $PackageName -AllVersions -Source https://api.nuget.org/v3/index.json -ErrorAction SilentlyContinue }
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    dotnet restore $ProjectDir

    foreach ($Project in $(Get-ChildItem -Path $pwd -Filter *.csproj -Recurse -ErrorAction SilentlyContinue -Force)) {
        foreach ($Package in $(dotnet list $Project.FullName package | Select-String -Pattern "^\s*>")) {
            # Ignore version ranges like [1.0,1.0)
            if ($Package.Line.Contains('[') -eq $false -and
                $Package.Line.Contains(']') -eq $false -and
                $Package.Line.Contains('(') -eq $false -and
                $Package.Line.Contains(')') -eq $false) {
                # Parse the version
                $PackageName = $Package -replace '^ *> ([a-zA-Z0-9\.]*) .*$', '$1' 
                $MajorVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$1' 
                $MinorVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$2' 
                $PatchVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$3' 

                Write-Output "Checking '$($Package.Line)'"
                $Available = $(&$FetchVersions -PackageName $PackageName | Where-Object {$_.Version -Match "^$MajorVersion\.$MinorVersion\.d+\..*$"})
                $HighestPatch = $Available | Sort-Object {[int]($_.Version.Split('.')[2])} | Select-Object -Last 1
                if ($null -ne $HighestPatch.Version -and $HighestPatch.Version -ne "$MajorVersion.$MinorVersion.$PatchVersion") {

                    Write-Output "Updating '$PackageName' from '$MajorVersion.$MinorVersion.$PatchVersion' to $($HighestPatch.Version)"

                    dotnet add $Project.FullName package $PackageName -v $HighestPatch.Version
                    
                }
            }
            else {
                Write-Output "Skipping '$($Package.Line)'"
            }
        }
    }

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
