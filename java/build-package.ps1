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
    $vaultCertChain = "$PWD/certchain.pem"
    Set-Content -Path $vaultCertChain -Value $CodeSigningKeyVaultCertificateData

    $jcaDownloadLink = "https://github.com/ebourg/jsign/releases/download/6.0/jsign-6.0.jar"
    $jcaProviderJar = "$PWD/jsign.jar"
    Write-Host "Downloading $jcaDownloadLink to $jcaProviderJar"
    Invoke-WebRequest $jcaDownloadLink -OutFile $jcaProviderJar

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
            "-DkeyvaultJcaJar=$jcaProviderJar" `
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

    Write-Host "Copying publishing bundle"
    Copy-Item target/central-publishing/central-bundle.zip $packagePath

    # Maven 3.10 writes local repository files into the staging directory, the
    # publishing plugin bundles them, and Central rejects the bundle because of them.
    Write-Host "Removing local repository files from the publishing bundle"
    $localRepoFiles = 'maven-metadata-local.xml', '_remote.repositories'
    $bundle = [System.IO.Compression.ZipFile]::Open("$packagePath/central-bundle.zip", 'Update')
    try {
        foreach ($entry in @($bundle.Entries)) {
            $parts = $entry.FullName -split '[\\/]'
            $name = $parts[-1]
            # Each file is matched together with its checksums, e.g. _remote.repositories.sha1
            if ($parts -contains '.locks' -or $localRepoFiles.Where({ $name -eq $_ -or $name.StartsWith("$_.") })) {
                Write-Host "Removing $($entry.FullName)"
                $entry.Delete()
            }
        }
    } finally {
        $bundle.Dispose()
    }
} finally {
    Write-Host "Leaving '$RepoName'"
    Pop-Location
}
