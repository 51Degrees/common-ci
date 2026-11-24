param (
    [Parameter(Mandatory)][string]$FetchScript,
    [string]$LicenseKey
)
$ErrorActionPreference = 'Stop'

# Prints the key of the prefetched assets. They change with the day, with the
# data license key they are downloaded with, and with the repository's
# ci/fetch-assets.ps1, which lists them. No other secret takes part, because
# no other secret decides what is downloaded, so a change to one does not make
# every repository download everything again.
$sha1 = [Security.Cryptography.SHA1]::Create()
$text = $LicenseKey + "`n" + (Get-Content -Raw -LiteralPath $FetchScript)
$hash = [Convert]::ToHexString($sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))
"$(Get-Date -Format FileDate)-$hash"
