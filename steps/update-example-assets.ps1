param (
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [string]$Tag = "",
    [string]$SourceRepo = "51Degrees/documentation",
    [string[]]$Assets = @(
        "examples-main.min.css",
        "examples-main.css",
        "examples.min.js",
        "examples.js"
    )
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Resolve the latest examples-assets-v* release when no tag is pinned, so the
# nightly run tracks the newest published assets.
if ([string]::IsNullOrWhiteSpace($Tag)) {
    $headers = @{ "User-Agent" = "51Degrees-ci" }
    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$SourceRepo/releases?per_page=100" -Headers $headers
    $Tag = ($releases | Where-Object { $_.tag_name -like "examples-assets-v*" } | Sort-Object -Property created_at | Select-Object -Last 1).tag_name
    if ([string]::IsNullOrWhiteSpace($Tag)) {
        throw "No examples-assets-v* release found in $SourceRepo."
    }
}
Write-Output "Using release $Tag from $SourceRepo"

# Download the release assets to a temp dir using the shared downloader.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "example-assets-$([System.Guid]::NewGuid().ToString('N'))"
& "$PSScriptRoot/../scripts/update-example-assets.ps1" -OutputDir $temp -Tag $Tag -Repo $SourceRepo -Assets $Assets

# Overwrite every committed copy of each asset already present in the repo.
# Only existing vendored copies are refreshed; new files are not added here.
foreach ($asset in $Assets) {
    $src = Join-Path $temp $asset
    $tracked = git -C $RepoName ls-files "*$asset"
    foreach ($rel in $tracked) {
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        Copy-Item -Path $src -Destination (Join-Path $RepoName $rel) -Force
        Write-Output "Refreshed $rel"
    }
}

Remove-Item -Recurse -Force $temp
