# Tests for steps/asset-cache.ps1, which encrypts the assets that are not free
# before the asset cache is saved and decrypts them after it is restored.
# Run with: Invoke-Pester ./steps/asset-cache.Tests.ps1
#
# The tests run the real openssl on files of random bytes. The key is a new
# random value for each run, held in the environment only.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'asset-cache.ps1'
    $script:Licensed = @('TAC-HashV41.hash', 'chargify.json', 'nested/51Degrees.csv')
    $script:Free = @('51Degrees-LiteV4.1.hash', 'ip-intelligence-evidence.yml')

    function New-RandomFile ([string]$Path, [int]$Size) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        $bytes = [byte[]]::new($Size)
        [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        [IO.File]::WriteAllBytes($Path, $bytes)
    }

    function Get-Hashes ([string]$Folder) {
        $hashes = @{}
        $root = (Resolve-Path -LiteralPath $Folder).Path
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
            $name = [IO.Path]::GetRelativePath($root, $file.FullName) -replace '\\', '/'
            $hashes[$name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        $hashes
    }

    # Moves the saved cache folder alone into a new work folder, as a new job
    # that restores the cache.
    function Copy-ToNewJob {
        $job = Join-Path ([IO.Path]::GetTempPath()) "asset-cache-$(New-Guid)"
        New-Item -ItemType Directory -Path $job | Out-Null
        Copy-Item -Recurse -LiteralPath (Join-Path $script:Work 'asset-cache') -Destination $job
        Remove-Item -Recurse -Force $script:Work
        $script:Work = $job
    }

    # Runs the step in its own work folder with the key set, or without it.
    function Invoke-Step ([string]$Work, [string]$Key, [switch]$Save, [switch]$Restore) {
        $before = $env:CACHE_ENCRYPTION_KEY
        $env:CACHE_ENCRYPTION_KEY = $Key
        Push-Location $Work
        try {
            if ($Save) { & $script:Step -Save 3>$null } else { & $script:Step -Restore }
        } finally {
            Pop-Location
            $env:CACHE_ENCRYPTION_KEY = $before
        }
    }
}

Describe 'asset-cache.ps1' {

    BeforeEach {
        $script:Key = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) "asset-cache-$(New-Guid)"
        foreach ($name in $script:Licensed + $script:Free) {
            New-RandomFile (Join-Path $script:Work "assets/$name") 70000
        }
        $script:Original = Get-Hashes (Join-Path $script:Work 'assets')
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue
    }

    It 'saves the free files as they are and every other file only encrypted' {
        Invoke-Step $script:Work $script:Key -Save | Should -BeTrue
        $saved = Get-Hashes (Join-Path $script:Work 'asset-cache')
        foreach ($name in $script:Free) {
            $saved[$name] | Should -Be $script:Original[$name]
        }
        foreach ($name in $script:Licensed) {
            $saved.ContainsKey($name) | Should -BeFalse -Because "$name is saved only encrypted"
            $saved.ContainsKey("$name.enc") | Should -BeTrue
        }
        # No saved file has the bytes of a file that is not free.
        $plain = @($script:Licensed | ForEach-Object { $script:Original[$_] })
        @($saved.Values | Where-Object { $_ -in $plain }) | Should -BeNullOrEmpty
    }

    It 'restores, with the key, the same bytes as the original files' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        Invoke-Step $script:Work $script:Key -Restore
        $restored = Get-Hashes (Join-Path $script:Work 'assets')
        $restored.Count | Should -Be $script:Original.Count
        foreach ($name in $script:Original.Keys) {
            $restored[$name] | Should -Be $script:Original[$name] -Because "$name comes back with the bytes it was saved with"
        }
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores, without the key, no file that is not free, and fails naming what is missing' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        $failure = $null
        try { Invoke-Step $script:Work '' -Restore } catch { $failure = $_.Exception.Message }
        $failure | Should -Match 'CACHE_ENCRYPTION_KEY is not set'
        foreach ($name in $script:Licensed) {
            $failure | Should -Match ([regex]::Escape($name))
        }
        $failure | Should -Not -Match ([regex]::Escape($script:Key))
        $restored = Get-Hashes (Join-Path $script:Work 'assets')
        @($restored.Keys | Sort-Object) | Should -Be @($script:Free | Sort-Object) -Because 'only the free files are restored'
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores, with another key, no file that is not free, and fails without printing either key' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        $other = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        $failure = $null
        try { Invoke-Step $script:Work $other -Restore } catch { $failure = $_.Exception.Message }
        $failure | Should -Match 'did not decrypt'
        $failure | Should -Not -Match ([regex]::Escape($script:Key))
        $failure | Should -Not -Match ([regex]::Escape($other))
        $restored = Get-Hashes (Join-Path $script:Work 'assets')
        @($restored.Keys | Sort-Object) | Should -Be @($script:Free | Sort-Object)
    }

    It 'saves nothing without the key when a file is not free' {
        Invoke-Step $script:Work '' -Save | Should -BeFalse
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'saves and restores free files alone without the key' {
        foreach ($name in $script:Licensed) {
            Remove-Item -LiteralPath (Join-Path $script:Work "assets/$name")
        }
        Invoke-Step $script:Work '' -Save | Should -BeTrue
        Copy-ToNewJob
        Invoke-Step $script:Work '' -Restore
        $restored = Get-Hashes (Join-Path $script:Work 'assets')
        @($restored.Keys | Sort-Object) | Should -Be @($script:Free | Sort-Object)
        foreach ($name in $script:Free) {
            $restored[$name] | Should -Be $script:Original[$name]
        }
    }

    It 'does nothing after a cache miss' {
        Remove-Item -Recurse -Force (Join-Path $script:Work 'assets')
        { Invoke-Step $script:Work '' -Restore } | Should -Not -Throw
        Join-Path $script:Work 'assets' | Should -Not -Exist
    }
}
