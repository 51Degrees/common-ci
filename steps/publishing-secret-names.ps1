<#
.SYNOPSIS
    Gives the publishing and setup secrets the names the scripts ask for.

.DESCRIPTION
    A caller that passes 'secrets: inherit' hands every secret over under its
    own repository or organisation name, such as PYPI_TOKEN. The publishing
    and setup scripts ask for the names callers used to map, such as
    PypiToken. For each one, this copies the repository secret to the asked
    name in the Keys hashtable, unless a caller already passed that name, so
    the scripts work either way.

    Test keys are not named here. They are read only under their _51DEGREES_
    names (steps/set-resource-keys.ps1).

    Only names are logged, never a value.

.PARAMETER Keys
    The secrets available to the job ($Options.Keys), changed in place.
#>
param(
    [hashtable]$Keys
)
$ErrorActionPreference = "Stop"

# The name a script asks for, from the name the secret has in the repository
# or organisation.
$Names = [ordered]@{
    MavenSettings = 'MAVEN_SETTINGS'
    JavaGpgKeyPassphrase = 'JAVA_GPG_KEY_PASSPHRASE'
    JavaPGP = 'JAVA_KEY_PGP_FILE'
    CodeSigningKeyVaultName = 'CODE_SIGNING_KEY_VAULT_NAME'
    CodeSigningKeyVaultUrl = 'CODE_SIGNING_KEY_VAULT_URL'
    CodeSigningKeyVaultClientId = 'CODE_SIGNING_KEY_VAULT_CLIENT_ID'
    CodeSigningKeyVaultTenantId = 'CODE_SIGNING_KEY_VAULT_TENANT_ID'
    CodeSigningKeyVaultClientSecret = 'CODE_SIGNING_KEY_VAULT_CLIENT_SECRET'
    CodeSigningKeyVaultCertificateName = 'CODE_SIGNING_KEY_VAULT_CERTIFICATE_NAME'
    CodeSigningKeyVaultCertificateData = 'CODE_SIGNING_KEY_VAULT_CERTIFICATE_DATA'
    PypiToken = 'PYPI_TOKEN'
    NginxKey = 'NGINX_PLUS_KEY'
    NginxCert = 'NGINX_PLUS_CERT'
    NginxJwtToken = 'NGINX_PLUS_JWT_TOKEN'
    NPMAuthToken = 'NPM_AUTH_TOKEN'
    ApiKey = 'NUGET_API_KEY'
    StrongNameKeyBase64 = 'STRONG_NAME_KEY_BASE64'
}

if ($null -eq $Keys) { return }

# GitHub gives secret names in capitals, and the hashtable parsed from JSON
# matches with case, so the repository name is looked up without it.
$byName = @{}
foreach ($name in @($Keys.Keys)) { $byName[$name.ToUpperInvariant()] = $name }

foreach ($asked in $Names.Keys) {
    if (-not [string]::IsNullOrWhiteSpace([string]$Keys[$asked])) { continue }
    $actual = $byName[$Names[$asked]]
    if (-not $actual) { continue }
    $value = [string]$Keys[$actual]
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $Keys[$asked] = $value
    Write-Host "Named $asked from $($Names[$asked])."
}
