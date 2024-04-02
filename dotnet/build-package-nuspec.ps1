
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$Name = "Release",
    [string]$Configuration = "Release",
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [string]$NuspecPath,
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

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    Write-Output "Building package for '$Name'"
   
    nuget pack $NuspecPath -NonInteractive -OutputDirectory "$PackagesFolder" -Properties config=$Configuration -version $Version

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
