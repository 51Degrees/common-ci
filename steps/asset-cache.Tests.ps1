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

    # The names of the files in the work folder's assets, in order.
    function Get-Restored {
        @((Get-Hashes (Join-Path $script:Work 'assets')).Keys | Sort-Object)
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

    # A folder whose openssl fails every time, for -Openssl failing.
    function New-FailingOpenssl {
        $folder = Join-Path ([IO.Path]::GetTempPath()) "asset-cache-openssl-$(New-Guid)"
        New-Item -ItemType Directory -Path $folder | Out-Null
        if ($IsWindows) {
            Set-Content -Path (Join-Path $folder 'openssl.cmd') -Value '@exit /b 1'
        } else {
            $file = Join-Path $folder 'openssl'
            Set-Content -Path $file -Value "#!/bin/sh`nexit 1"
            chmod +x $file
        }
        $folder
    }

    # Runs the step in its own work folder with the key set, or without it,
    # and keeps its warnings in $script:Warnings. With -Openssl missing, the
    # PATH holds no openssl, and with -Openssl failing, an openssl that fails.
    function Invoke-Step ([string]$Work, [string]$Key, [switch]$Save, [switch]$Restore,
        [ValidateSet('', 'missing', 'failing')][string]$Openssl = '') {
        $before = $env:CACHE_ENCRYPTION_KEY
        $path = $env:PATH
        $env:CACHE_ENCRYPTION_KEY = $Key
        $fake = $null
        if ($Openssl -eq 'missing') { $env:PATH = $Work }
        if ($Openssl -eq 'failing') { $fake = New-FailingOpenssl; $env:PATH = $fake }
        $stepWarnings = $null
        Push-Location $Work
        try {
            if ($Save) {
                & $script:Step -Save -WarningVariable stepWarnings 3>$null
            } else {
                & $script:Step -Restore -WarningVariable stepWarnings 3>$null
            }
        } finally {
            Pop-Location
            $env:CACHE_ENCRYPTION_KEY = $before
            $env:PATH = $path
            if ($fake) { Remove-Item -Recurse -Force $fake }
            $script:Warnings = (@($stepWarnings) | ForEach-Object { "$_" }) -join "`n"
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
        $script:Warnings | Should -BeNullOrEmpty
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores, without the key, the free files alone, and warns naming the others' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        { Invoke-Step $script:Work '' -Restore } | Should -Not -Throw
        $script:Warnings | Should -Match 'CACHE_ENCRYPTION_KEY is not set'
        foreach ($name in $script:Licensed) {
            $script:Warnings | Should -Match ([regex]::Escape($name))
        }
        $script:Warnings | Should -Not -Match ([regex]::Escape($script:Key))
        Get-Restored | Should -Be @($script:Free | Sort-Object) -Because 'only the free files are restored'
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores, with another key, the free files alone, and warns without printing either key' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        $other = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        { Invoke-Step $script:Work $other -Restore } | Should -Not -Throw
        $script:Warnings | Should -Match 'did not decrypt'
        $script:Warnings | Should -Not -Match ([regex]::Escape($script:Key))
        $script:Warnings | Should -Not -Match ([regex]::Escape($other))
        Get-Restored | Should -Be @($script:Free | Sort-Object)
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores every file that decrypts, and warns naming one that is cut short' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        $short = Join-Path $script:Work "asset-cache/$($script:Licensed[0]).enc"
        $bytes = [IO.File]::ReadAllBytes($short)
        [IO.File]::WriteAllBytes($short, $bytes[0..($bytes.Length - 40)])
        { Invoke-Step $script:Work $script:Key -Restore } | Should -Not -Throw
        $script:Warnings | Should -Match ([regex]::Escape($script:Licensed[0]))
        Get-Restored | Should -Be @(($script:Free + $script:Licensed[1..2]) | Sort-Object)
        Join-Path $script:Work "assets/$($script:Licensed[0]).partial" | Should -Not -Exist
    }

    It 'restores no encrypted file when the cache names one outside the assets folder, and warns naming it' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        $manifestPath = Join-Path $script:Work 'asset-cache/encrypted.json'
        $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
        $manifest['../outside.bin'] = $manifest[$script:Licensed[0]]
        $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        { Invoke-Step $script:Work $script:Key -Restore } | Should -Not -Throw
        $script:Warnings | Should -Match ([regex]::Escape('../outside.bin'))
        Get-Restored | Should -Be @($script:Free | Sort-Object)
        Join-Path $script:Work 'outside.bin' | Should -Not -Exist
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'restores, without openssl, the free files alone, and warns' {
        Invoke-Step $script:Work $script:Key -Save | Out-Null
        Copy-ToNewJob
        { Invoke-Step $script:Work $script:Key -Restore -Openssl missing } | Should -Not -Throw
        $script:Warnings | Should -Match 'openssl'
        Get-Restored | Should -Be @($script:Free | Sort-Object)
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'saves nothing without the key when a file is not free' {
        Invoke-Step $script:Work '' -Save | Should -BeFalse
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'saves nothing without openssl when a file is not free, and warns' {
        { $script:Result = Invoke-Step $script:Work $script:Key -Save -Openssl missing } | Should -Not -Throw
        $script:Result | Should -BeFalse
        $script:Warnings | Should -Match 'openssl'
        Join-Path $script:Work 'asset-cache' | Should -Not -Exist
    }

    It 'saves nothing when openssl fails, and warns naming the file' {
        { $script:Result = Invoke-Step $script:Work $script:Key -Save -Openssl failing } | Should -Not -Throw
        $script:Result | Should -BeFalse
        $script:Warnings | Should -Match 'could not encrypt'
        $script:Warnings | Should -Not -Match ([regex]::Escape($script:Key))
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
