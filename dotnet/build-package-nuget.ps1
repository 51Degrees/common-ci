
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release",
    [string]$Configuration = "Release",
    [string]$Version,
    [string]$SolutionName,
    # Regex pattern to filter out projects that will not be published as a package 
    [string]$SearchPattern = "^(?!.*(Test|GenerateConfig))Project\(.*csproj",
    [Parameter(Mandatory=$true)]
    [string]$CodeSigningKeyVaultUrl,
    [Parameter(Mandatory=$true)]
    [string]$CodeSigningKeyVaultClientId,
    [Parameter(Mandatory=$true)]
    [string]$CodeSigningKeyVaultTenantId,
    [Parameter(Mandatory=$true)]
    [string]$CodeSigningKeyVaultClientSecret,
    [Parameter(Mandatory=$true)]
    [string]$CodeSigningKeyVaultCertificateName
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$PackagesFolder = [IO.Path]::Combine($pwd, "package")
$CodeSigningCertFile = "51Degrees Private Code Signing Certificate.pfx"

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    Write-Output "Building package for '$Name'"
   
    $Projects = Get-Content "$SolutionName" |
    Select-String $SearchPattern |
        ForEach-Object {
            $projectParts = $_ -Split '[,=]' | ForEach-Object { $_.Trim('[ "{}]') };
            New-Object PSObject -Property @{
                Name = $projectParts[1];
                File = $projectParts[2];
                Guid = $projectParts[3]
            }
    }
    foreach($Project in $Projects){
        dotnet pack $Project.File -o "$PackagesFolder" -c $Configuration /p:PackageVersion=$Version /p:BuiltOnCI=true
    }

    Write-Output "Installing NuGetKeyVaultSignTool"
    dotnet tool install -g NuGetKeyVaultSignTool || $(throw "NuGetKeyVaultSignTool installation failed")

    Write-Output "Signing packages"
    NuGetKeyVaultSignTool sign -f "$PackagesFolder\*.nupkg" `
        --file-digest sha256 `
        --timestamp-digest sha256 `
        --timestamp-rfc3161 http://rfc3161timestamp.globalsign.com/advanced `
        --azure-key-vault-url $CodeSigningKeyVaultUrl `
        --azure-key-vault-client-id $CodeSigningKeyVaultClientId `
        --azure-key-vault-tenant-id $CodeSigningKeyVaultTenantId `
        --azure-key-vault-client-secret $CodeSigningKeyVaultClientSecret `
        --azure-key-vault-certificate $CodeSigningKeyVaultCertificateName || $(throw "package signing failed")

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
