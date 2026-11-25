<#
.SYNOPSIS
    Puts the assets into the folder the asset cache saves, encrypting every
    file that is not free, or takes them back out after a restore.

.DESCRIPTION
    The asset cache saves and restores the asset-cache folder, never the
    assets folder itself.

    With -Save, the assets folder is copied into the cache folder. A free file,
    one that free-assets.psd1 names, is copied as it is. Every other file is
    encrypted with openssl, AES-256-CBC with a key derived by PBKDF2 from
    CACHE_ENCRYPTION_KEY, and written as <name>.enc, and the SHA-256 of its
    plain bytes goes into encrypted.json. Without CACHE_ENCRYPTION_KEY or
    openssl, or when openssl cannot encrypt a file, assets that hold any file
    that is not free are not put into the cache folder, the step warns, and
    nothing is saved. The script returns whether there is a folder to save.

    With -Restore, the free files are moved from the cache folder into the
    assets folder, and each encrypted file is decrypted into it and checked
    against its SHA-256. Without CACHE_ENCRYPTION_KEY or openssl, or when a
    file does not decrypt to the bytes that were saved, that file is not
    restored, and the step warns naming it and succeeds, leaving it for the
    steps that fetch the assets to download. When the cache names a file
    outside the assets folder, no encrypted file is restored. The cache folder
    is removed either way. With no cache folder, as after a cache miss,
    nothing is done.

    openssl reads the key from the environment, never from its command line,
    and nothing here prints it.

.PARAMETER Save
    Puts the assets into the cache folder, before the cache is saved.

.PARAMETER Restore
    Takes the assets out of the cache folder, after the cache is restored.

.PARAMETER Assets
    The assets folder. Defaults to assets.

.PARAMETER Cache
    The folder the cache step saves and restores. Defaults to asset-cache.
#>
param(
    [Parameter(Mandatory, ParameterSetName = 'Save')][switch]$Save,
    [Parameter(Mandatory, ParameterSetName = 'Restore')][switch]$Restore,
    [string]$Assets = 'assets',
    [string]$Cache = 'asset-cache'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$free = @((Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'free-assets.psd1')).Keys)
$manifestName = 'encrypted.json'
$cipher = @('-aes-256-cbc', '-pbkdf2', '-iter', '600000', '-md', 'sha256')
$hasKey = -not [string]::IsNullOrEmpty($env:CACHE_ENCRYPTION_KEY)
$hasOpenssl = [bool](Get-Command openssl -CommandType Application -ErrorAction SilentlyContinue)

# The files under a folder, as paths relative to it with forward slashes.
function Get-RelativeFile ([string]$Folder) {
    $root = (Resolve-Path -LiteralPath $Folder).Path
    Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        [IO.Path]::GetRelativePath($root, $_.FullName) -replace '\\', '/'
    }
}

# Runs openssl enc with the key from the environment. Its own messages are
# dropped, and the caller names the file that failed.
function Invoke-Enc ([string[]]$Arguments) {
    & openssl enc @Arguments -pass env:CACHE_ENCRYPTION_KEY 2>$null
    return $LASTEXITCODE -eq 0
}

if ($Save) {
    if (Test-Path -LiteralPath $Cache) {
        Remove-Item -LiteralPath $Cache -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath $Assets -PathType Container)) {
        return $false
    }
    $files = @(Get-RelativeFile $Assets)
    $encrypted = @($files | Where-Object { $_ -cnotin $free })
    if ($encrypted.Count -gt 0 -and -not $hasKey) {
        Write-Warning "CACHE_ENCRYPTION_KEY is not set, so the assets are not saved to the cache. These files are saved only encrypted: $($encrypted -join ', ')"
        return $false
    }
    if ($encrypted.Count -gt 0 -and -not $hasOpenssl) {
        Write-Warning "openssl is not on the PATH, so the assets are not saved to the cache. These files are saved only encrypted: $($encrypted -join ', ')"
        return $false
    }
    New-Item -ItemType Directory -Path $Cache | Out-Null
    $manifest = [ordered]@{}
    foreach ($file in $files) {
        $source = Join-Path $Assets $file
        $target = Join-Path $Cache $file
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        if ($file -cin $free) {
            Copy-Item -LiteralPath $source -Destination $target
            continue
        }
        if (-not (Invoke-Enc (@('-e') + $cipher + @('-salt', '-in', $source, '-out', "$target.enc")))) {
            Remove-Item -LiteralPath $Cache -Recurse -Force
            Write-Warning "openssl could not encrypt $file, so the assets are not saved to the cache."
            return $false
        }
        $manifest[$file] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Cache $manifestName)
    return $true
}

if (-not (Test-Path -LiteralPath $Cache -PathType Container)) {
    return
}
try {
    New-Item -ItemType Directory -Force -Path $Assets | Out-Null
    foreach ($file in @(Get-RelativeFile $Cache)) {
        if ($file -cin $free) {
            Move-Item -LiteralPath (Join-Path $Cache $file) -Destination (Join-Path $Assets $file) -Force
        }
    }

    $manifestPath = Join-Path $Cache $manifestName
    $manifest = @{}
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -AsHashtable
    }
    $encrypted = @($manifest.Keys | Sort-Object)
    if ($encrypted.Count -eq 0) {
        return
    }
    $outside = @($encrypted | Where-Object { [IO.Path]::IsPathRooted($_) -or $_ -match '(^|[\\/])\.\.([\\/]|$)' })
    if ($outside.Count -gt 0) {
        Write-Warning "The asset cache names files outside the assets folder, so nothing encrypted is restored: $($outside -join ', '). The steps that fetch the assets download what is missing."
        return
    }
    if (-not $hasKey) {
        Write-Warning "CACHE_ENCRYPTION_KEY is not set, so these files from the asset cache are not restored: $($encrypted -join ', '). The step that restores the asset cache sets it from the CACHE_ENCRYPTION_KEY secret. The steps that fetch the assets download what is missing."
        return
    }
    if (-not $hasOpenssl) {
        Write-Warning "openssl is not on the PATH, so these files from the asset cache are not restored: $($encrypted -join ', '). The steps that fetch the assets download what is missing."
        return
    }

    $failed = @()
    foreach ($file in $encrypted) {
        $target = Join-Path $Assets $file
        $partial = "$target.partial"
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        $done = Invoke-Enc (@('-d') + $cipher + @('-in', (Join-Path $Cache "$file.enc"), '-out', $partial))
        if ($done -and (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -eq $manifest[$file]) {
            Move-Item -LiteralPath $partial -Destination $target -Force
        } else {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            $failed += $file
        }
    }
    if ($failed.Count -gt 0) {
        Write-Warning "These files from the asset cache did not decrypt to the bytes that were saved, so they are not restored: $($failed -join ', '). CACHE_ENCRYPTION_KEY may not be the key they were saved with. The steps that fetch the assets download what is missing."
    }
} finally {
    Remove-Item -LiteralPath $Cache -Recurse -Force -ErrorAction SilentlyContinue
}
