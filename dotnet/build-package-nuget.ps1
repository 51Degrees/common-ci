
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [string]$ProjectDir = ".",
    [string]$Name = "Release",
    [string]$Configuration = "Release",
    [string]$Version,
    [string]$SolutionName,
    # Regex pattern to filter out projects that will not be published as a package
    [string]$SearchPattern = "^(?!.*(Test|GenerateConfig))Project\(.*csproj"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
# The packages are signed with the signing secrets, which the job that signs
# exports under these names. Each is read at the point of use below.
foreach ($name in '_51DEGREES_SIGN_KEY_VAULT_URL', '_51DEGREES_SIGN_KEY_VAULT_CLIENT_ID',
    '_51DEGREES_SIGN_KEY_VAULT_TENANT_ID', '_51DEGREES_SIGN_KEY_VAULT_CLIENT_SECRET',
    '_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_NAME') {
    if ([string]::IsNullOrWhiteSpace((Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue).Value)) {
        throw "$name is not set, so the packages cannot be signed."
    }
}

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)
$PackagesFolder = New-Item -ItemType directory -Force "$PWD/package"

Write-Output "Entering '$RepoPath'"
Push-Location $RepoPath

try {
    Write-Output "Building package for '$Name'"

    $packArgs = @(
        "--output=$PackagesFolder"
        "--configuration=$Configuration"
        "/p:PackageVersion=$Version"
        "/p:Version=$Version"
        "/p:BuiltOnCI=true"
        "/p:ContinuousIntegrationBuild=true"
    )
    $env:Version = $Version
    if ($SolutionName -and $SearchPattern) {
        Get-Content $SolutionName | Select-String $SearchPattern | ForEach-Object {
            $projectParts = $_ -Split '[,=]' | ForEach-Object { $_.Trim('[ "{}]') };
            $file = $projectParts[2];
            dotnet pack $packArgs $file || $(throw "package packing failed")
        }
    } else {
        dotnet pack $packArgs || $(throw "package packing failed")
    }

    Write-Output "Installing NuGetKeyVaultSignTool"
    dotnet tool install -g NuGetKeyVaultSignTool || $(throw "NuGetKeyVaultSignTool installation failed")

    Write-Output "Signing packages"
    # The signing tool finds the packages only when the separator before the
    # wildcard is the one the system uses, which Join-Path gives.
    $toSign = Join-Path $PackagesFolder '*.nupkg'
    NuGetKeyVaultSignTool sign -f "$toSign" `
        --file-digest sha256 `
        --timestamp-digest sha256 `
        --timestamp-rfc3161 http://rfc3161timestamp.globalsign.com/advanced `
        --azure-key-vault-url $env:_51DEGREES_SIGN_KEY_VAULT_URL `
        --azure-key-vault-client-id $env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_ID `
        --azure-key-vault-tenant-id $env:_51DEGREES_SIGN_KEY_VAULT_TENANT_ID `
        --azure-key-vault-client-secret $env:_51DEGREES_SIGN_KEY_VAULT_CLIENT_SECRET `
        --azure-key-vault-certificate $env:_51DEGREES_SIGN_KEY_VAULT_CERTIFICATE_NAME || $(throw "package signing failed")

}
finally {

    Write-Output "Leaving '$RepoPath'"
    Pop-Location

}

exit $LASTEXITCODE
