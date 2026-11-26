param (
    [Parameter(Mandatory)][string]$FetchScript,
    # The key as it was this many days ago, for the entry an earlier day saved.
    [int]$DaysAgo = 0
)
$ErrorActionPreference = 'Stop'

# Prints the key of the prefetched assets. They change with the day and with
# the repository's ci/fetch-assets.ps1, which lists them. No secret takes
# part, so a change to one does not make every repository download everything
# again.
$sha1 = [Security.Cryptography.SHA1]::Create()
$text = Get-Content -Raw -LiteralPath $FetchScript
$hash = [Convert]::ToHexString($sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))
"$((Get-Date).AddDays(-$DaysAgo).ToString('yyyyMMdd'))-$hash"
