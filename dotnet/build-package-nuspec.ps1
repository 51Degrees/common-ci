
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$Name = "Release",
    [string]$Configuration = "Release",
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [string]$NuspecPath
)
# The packages are signed with the signing secrets, which the job that signs
# exports under these names. Each is read at the point of use below.
foreach ($name in '_51DEGREES_CODE_SIGNING_KEY_VAULT_URL', '_51DEGREES_CODE_SIGNING_KEY_VAULT_CLIENT_ID',
    '_51DEGREES_CODE_SIGNING_KEY_VAULT_TENANT_ID', '_51DEGREES_CODE_SIGNING_KEY_VAULT_CLIENT_SECRET',
    '_51DEGREES_CODE_SIGNING_KEY_VAULT_CERTIFICATE_NAME') {
    if ([string]::IsNullOrWhiteSpace((Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue).Value)) {
        throw "$name is not set, so the packages cannot be signed."
    }
}

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$PackagesFolder = [IO.Path]::Combine($pwd, "package")

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    Write-Output "Building package for '$Name'"

    $env:Version = $Version
    nuget pack $NuspecPath -NonInteractive -OutputDirectory "$PackagesFolder" -Properties config=$Configuration -version $Version

    Write-Output "Installing NuGetKeyVaultSignTool"
    dotnet tool install -g NuGetKeyVaultSignTool || $(throw "NuGetKeyVaultSignTool installation failed")

    Write-Output "Signing packages"
    NuGetKeyVaultSignTool sign -f "$PackagesFolder\*.nupkg" `
        --file-digest sha256 `
        --timestamp-digest sha256 `
        --timestamp-rfc3161 http://rfc3161timestamp.globalsign.com/advanced `
        --azure-key-vault-url $env:_51DEGREES_CODE_SIGNING_KEY_VAULT_URL `
        --azure-key-vault-client-id $env:_51DEGREES_CODE_SIGNING_KEY_VAULT_CLIENT_ID `
        --azure-key-vault-tenant-id $env:_51DEGREES_CODE_SIGNING_KEY_VAULT_TENANT_ID `
        --azure-key-vault-client-secret $env:_51DEGREES_CODE_SIGNING_KEY_VAULT_CLIENT_SECRET `
        --azure-key-vault-certificate $env:_51DEGREES_CODE_SIGNING_KEY_VAULT_CERTIFICATE_NAME || $(throw "package signing failed")

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
