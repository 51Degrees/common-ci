param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name,
    [string]$Source = "https://api.nuget.org/v3/index.json",
    [string]$SourceUser = "",
    [string]$SourceKey = ""
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

            try {
                if ($SourceUser -ne "" -and $SourceKey -ne "") {
                    $Password = ConvertTo-SecureString $SourceKey -AsPlainText -Force
                    $Credential = New-Object System.Management.Automation.PSCredential($SourceUser, $Password)
                    Register-PackageSource -Name SpecifiedSource -Location $Source -Credential $Credential
                    Find-PackageProvider
                    $Available = $(Find-Package -Name $PackageName -AllVersions -Source $Source -PackageProvider "NuGet" | Where-Object {$_.Version -Match "^$MajorVersion\.$MinorVersion\..*$"})
                }
                else {
                    $Available = $(Find-Package -Name $PackageName -AllVersions -Source $Source | Where-Object {$_.Version -Match "^$MajorVersion\.$MinorVersion\..*$"})
                }
                $HighestPatch = $Available | Sort-Object {[int]($_.Version.Split('.')[2])} | Select-Object -Last 1
    
                if ($HighestPatch.Version -ne "$MajorVersion.$MinorVersion.$PatchVersion") {
    
                    Write-Output "Updating '$PackageName' from '$MajorVersion.$MinorVersion.$PatchVersion' to $($HighestPatch.Version)"
    
                    dotnet add $Project.FullName package $PackageName -v $HighestPatch.Version
                    
                }
            }
            catch {
                Write-Output "Could not find the package '$PackageName' in source '$Source' : $_"
            }
        }
    }

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
