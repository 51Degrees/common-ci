param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    
    dotnet restore $ProjectDir

    foreach ($Project in $(Get-ChildItem -Path $pwd -Filter *.csproj -Recurse -ErrorAction SilentlyContinue -Force)) {
        foreach ($Package in $(dotnet list $Project.FullName package --outdated | Select-String -Pattern "^\s*>")) {
            $PackageName = $Package -replace '^ *> ([a-zA-Z0-9\.]*) .*$', '$1' 
            $MajorVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$1' 
            $MinorVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$2' 
            $PatchVersion = $Package -replace '^ *> [a-zA-Z0-9\.]* *([0-9]*)\.([0-9]*)\.([0-9]*).*$', '$3' 

            $Available = $(Find-Package -Name $PackageName -AllVersions -Source https://api.nuget.org/v3/index.json | Where-Object {$_.Version -Match "^$MajorVersion\.$MinorVersion\..*$"})
            $HighestPatch = $Available | Sort-Object {[int]($_.Version.Split('.')[2])} | Select-Object -Last 1

            if ($HighestPatch.Version -ne "$MajorVersion.$MinorVersion.$PatchVersion") {

                Write-Output "Updating '$PackageName' from '$MajorVersion.$MinorVersion.$PatchVersion' to $($HighestPatch.Version)"

                dotnet add $Project.FullName package $PackageName -v $HighestPatch.Version
                
            }
        }
    }

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
