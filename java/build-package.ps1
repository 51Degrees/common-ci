param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Version,
    [string]$Name,
    [string[]]$ExtraArgs,
    # Folders to set the version in, relative to the repository. A repository
    # whose root pom.xml is not the parent of its package trees lists each tree.
    [string[]]$VersionPaths = @('.')
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The packages are signed with the signing secrets, which the job that signs
# exports under these names. Each is read at the point of use below.
foreach ($name in '_51DEGREES_SIGN_JAVA_KEY_PGP_FILE', '_51DEGREES_SIGN_JAVA_GPG_KEY_PASSPHRASE',
    '_51DEGREES_SIGN_KEY_VAULT_NAME', '_51DEGREES_SIGN_KEY_VAULT_URL',
    '_51DEGREES_SIGN_KEY_VAULT_CLIENT_ID', '_51DEGREES_SIGN_KEY_VAULT_TENANT_ID',
    '_51DEGREES_SIGN_KEY_VAULT_CLIENT_SECRET', '_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_NAME',
    '_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_DATA') {
    if ([string]::IsNullOrWhiteSpace((Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue).Value)) {
        throw "$name is not set, so the packages cannot be signed."
    }
}

$packagePath = New-Item -ItemType directory -Force -Path package
$mvnLocalRepo = mvn help:evaluate -Dexpression="settings.localRepository" -q -DforceStdout
$mvnSettings = "$PWD/java/settings.xml"

Write-Host "Entering '$RepoName'"
Push-Location $RepoName
try {
    foreach ($versionPath in $VersionPaths) {
        Write-Host "Setting package version to '$Version' in '$versionPath'"
        Push-Location $versionPath
        try {
            mvn versions:set --batch-mode --no-transfer-progress "-DnewVersion=$Version"
        } finally {
            Pop-Location
        }
    }

    Write-Host "Writing certificate chain"
    $vaultCertChain = "$PWD/certchain.pem"
    Set-Content -Path $vaultCertChain -Value $env:_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_DATA

    $jcaDownloadLink = "https://github.com/ebourg/jsign/releases/download/6.0/jsign-6.0.jar"
    $jcaProviderJar = "$PWD/jsign.jar"
    Write-Host "Downloading $jcaDownloadLink to $jcaProviderJar"
    Invoke-WebRequest $jcaDownloadLink -OutFile $jcaProviderJar

    Write-Host "Importing PGP file"
    $pgpFile = "Java Maven GPG Key Private.pgp"
    Set-Content -Path $pgpFile -Value $env:_51DEGREES_SIGN_JAVA_KEY_PGP_FILE
    Write-Output $env:_51DEGREES_SIGN_JAVA_GPG_KEY_PASSPHRASE | gpg --import --batch --yes --passphrase-fd 0 $pgpFile
    gpg --list-keys

    try {
        az login --service-principal --allow-no-subscriptions `
            --username $env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_ID `
            --password $env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_SECRET `
            --tenant $env:_51DEGREES_SIGN_KEY_VAULT_TENANT_ID `

        $vaultAccessToken = (az account get-access-token --resource "https://vault.azure.net" --tenant $env:_51DEGREES_SIGN_KEY_VAULT_TENANT_ID | ConvertFrom-Json).accessToken

        Write-Host "Deploying '$Name' locally"
        mvn deploy --batch-mode --no-transfer-progress --settings $mvnSettings $ExtraArgs `
            "-DskipTests" `
            "-Dskippackagesign=false" `
            "-Dgpg.passphrase=$env:_51DEGREES_SIGN_JAVA_GPG_KEY_PASSPHRASE" `
            "-DkeyvaultJcaJar=$jcaProviderJar" `
            "-DkeyvaultVaultName=$env:_51DEGREES_SIGN_KEY_VAULT_NAME" `
            "-DkeyvaultUrl=$env:_51DEGREES_SIGN_KEY_VAULT_URL" `
            "-DkeyvaultClientId=$env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_ID" `
            "-DkeyvaultTenant=$env:_51DEGREES_SIGN_KEY_VAULT_TENANT_ID" `
            "-DkeyvaultClientSecret=$env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_SECRET" `
            "-DkeyvaultCertName=$env:_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_NAME" `
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

    # A reactor that holds several publishing trees writes one bundle for all of
    # them, under the first tree, so look for it below the repository folder.
    Write-Host "Copying publishing bundle"
    $bundles = @(Get-ChildItem -Recurse -File -Filter central-bundle.zip |
        Where-Object { $_.Directory.Name -eq 'central-publishing' })
    if ($bundles.Count -ne 1) {
        $found = if ($bundles) { ": $($bundles.FullName -join ', ')" } else { '' }
        throw "Expected exactly one central-publishing/central-bundle.zip below '$RepoName' but found $($bundles.Count)$found"
    }
    Write-Host "Found $($bundles[0].FullName)"
    Copy-Item $bundles[0].FullName $packagePath

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
