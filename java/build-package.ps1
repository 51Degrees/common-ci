param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$JavaGpgKeyPassphrase,
    [Parameter(Mandatory)][string]$JavaPGP,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultName,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultUrl,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultClientId,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultTenantId,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultClientSecret,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultCertificateName,
    [Parameter(Mandatory)][string]$CodeSigningKeyVaultCertificateData,
    [string]$Name,
    [string]$ProjectDir = ".",
    [string[]]$ExtraArgs
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$packagePath = New-Item -ItemType directory -Force -Path package
$mvnLocalRepo = mvn help:evaluate -Dexpression="settings.localRepository" -q -DforceStdout
$mvnSettings = "$PWD/java/settings.xml"

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    Write-Host "Setting package version to '$Version'"
    mvn versions:set --batch-mode --no-transfer-progress "-DnewVersion=$Version"

    Write-Host "Writing certificate chain"
    $vaultCertChain = "certchain.pem"
    Set-Content -Path $vaultCertChain -Value $CodeSigningKeyVaultCertificateData

    Write-Host "Downloading $jcaDownloadLink"
    $jcaDownloadLink = "https://github.com/ebourg/jsign/releases/download/6.0/jsign-6.0.jar"
    $jcaProviderJar = "jsign.jar"
    Invoke-WebRequest $jcaDownloadLink -OutFile $JcaProviderJar

    Write-Host "Importing PGP file"
    $pgpFile = "Java Maven GPG Key Private.pgp"
    Set-Content -Path $pgpFile -Value $JavaPGP
    Write-Output $JavaGpgKeyPassphrase | gpg --import --batch --yes --passphrase-fd 0 $pgpFile
    gpg --list-keys

    try {
        az login --service-principal --allow-no-subscriptions `
            --username $CodeSigningKeyVaultClientId `
            --password $CodeSigningKeyVaultClientSecret `
            --tenant $CodeSigningKeyVaultTenantId `

        $vaultAccessToken = (az account get-access-token --resource "https://vault.azure.net" --tenant $CodeSigningKeyVaultTenantId | ConvertFrom-Json).accessToken

        Write-Host "Deploying '$Name' locally"
        mvn deploy --batch-mode --no-transfer-progress --settings $mvnSettings $ExtraArgs `
            "-DskipTests" `
            "-Dskippackagesign=false" `
            "-Dgpg.passphrase=$JavaGpgKeyPassphrase" `
            "-DkeyvaultJcaJar=$JcaProviderJar" `
            "-DkeyvaultVaultName=$CodeSigningKeyVaultName" `
            "-DkeyvaultUrl=$CodeSigningKeyVaultUrl" `
            "-DkeyvaultClientId=$CodeSigningKeyVaultClientId" `
            "-DkeyvaultTenant=$CodeSigningKeyVaultTenantId" `
            "-DkeyvaultClientSecret=$CodeSigningKeyVaultClientSecret" `
            "-DkeyvaultCertName=$CodeSigningKeyVaultCertificateName" `
            "-DkeyvaultCertChain=$vaultCertChain" `
            "-DkeyvaultAccessToken=$vaultAccessToken" `
            "-DskipPublishing=true"
    } finally {
        az logout
    }

    Write-Host "Maven local 51d repo contents:"
    Get-ChildItem "$mvnLocalRepo/com/51degrees"
    
    Write-Host "Copying 51degrees packages from local repo"
    Copy-Item -Recurse $mvnLocalRepo/com/51degrees $packagePath

    Write-Host "Copying local maven staging directory"
    Copy-Item -Recurse target $packagePath
} finally {
    Write-Host "Leaving '$RepoPath'"
    Pop-Location
}
