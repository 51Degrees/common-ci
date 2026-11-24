# Tests for steps/prefetch-cache-key.ps1 and steps/free-data-cache-key.ps1.
# Run with: Invoke-Pester ./steps/prefetch-cache-keys.Tests.ps1

BeforeAll {
    $script:PrefetchKey = Join-Path $PSScriptRoot 'prefetch-cache-key.ps1'
    $script:FreeDataKey = Join-Path $PSScriptRoot 'free-data-cache-key.ps1'
    $script:Action = Join-Path $PSScriptRoot '../.github/actions/prefetch_assets/action.yml'
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) "prefetch-cache-keys-$(New-Guid)"
    New-Item -ItemType Directory -Path $Work | Out-Null
    $script:FetchScript = Join-Path $Work 'fetch-assets.ps1'
    Set-Content -Path $FetchScript -Value "./steps/fetch-assets.ps1 -Assets 'TAC-HashV41.hash'"

    # A stand-in clone of the data repository.
    function New-Clone {
        $clone = Join-Path $script:Work "data-$(New-Guid)"
        New-Item -ItemType Directory -Path "$clone/device-detection", "$clone/.git" | Out-Null
        Set-Content -Path "$clone/device-detection/51Degrees-LiteV4.1.hash.link" -Value 'https://example.com/lite'
        Set-Content -Path "$clone/get-data-files.ps1" -Value 'script'
        Set-Content -Path "$clone/.git/HEAD" -Value 'ref: refs/heads/main'
        $clone
    }
}

AfterAll {
    Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue
}

Describe 'prefetch-cache-key.ps1' {

    It 'starts with the day' {
        & $PrefetchKey -FetchScript $FetchScript -LicenseKey 'key' |
            Should -BeLike "$(Get-Date -Format FileDate)-*"
    }

    It 'is the same for the same license key and asset list' {
        & $PrefetchKey -FetchScript $FetchScript -LicenseKey 'key' |
            Should -Be (& $PrefetchKey -FetchScript $FetchScript -LicenseKey 'key')
    }

    It 'changes with the license key' {
        & $PrefetchKey -FetchScript $FetchScript -LicenseKey 'key' |
            Should -Not -Be (& $PrefetchKey -FetchScript $FetchScript -LicenseKey 'other')
    }

    It 'changes with the asset list' {
        $other = Join-Path $Work 'other-fetch-assets.ps1'
        Set-Content -Path $other -Value "./steps/fetch-assets.ps1 -Assets '51Degrees.csv'"
        & $PrefetchKey -FetchScript $FetchScript -LicenseKey 'key' |
            Should -Not -Be (& $PrefetchKey -FetchScript $other -LicenseKey 'key')
    }

    It 'does not hold the license key' {
        & $PrefetchKey -FetchScript $FetchScript -LicenseKey 'license-key-value' |
            Should -Not -BeLike '*license-key-value*'
    }

    It 'is all the action passes to the key, with no other secret' {
        $hash = (Get-Content -Raw $Action) -split '- name: Check if cached' | Select-Object -First 1
        $hash | Should -Match 'prefetch-cache-key\.ps1'
        $hash | Should -Not -Match 'inputs\.secrets'
    }
}

Describe 'free-data-cache-key.ps1' {

    It 'starts with the week' {
        $today = Get-Date
        $week = '{0}W{1:00}' -f [Globalization.ISOWeek]::GetYear($today), [Globalization.ISOWeek]::GetWeekOfYear($today)
        & $FreeDataKey -Repository (New-Clone) | Should -BeLike "free-data-$week-*"
    }

    It 'is the same for two clones of the same files' {
        & $FreeDataKey -Repository (New-Clone) | Should -Be (& $FreeDataKey -Repository (New-Clone))
    }

    It 'changes when a link changes' {
        $clone = New-Clone
        Set-Content -Path "$clone/device-detection/51Degrees-LiteV4.1.hash.link" -Value 'https://example.com/other'
        & $FreeDataKey -Repository $clone | Should -Not -Be (& $FreeDataKey -Repository (New-Clone))
    }

    It 'changes when another file in the clone changes' {
        $clone = New-Clone
        Set-Content -Path "$clone/get-data-files.ps1" -Value 'changed'
        & $FreeDataKey -Repository $clone | Should -Not -Be (& $FreeDataKey -Repository (New-Clone))
    }

    It 'ignores the .git folder' {
        $clone = New-Clone
        Set-Content -Path "$clone/.git/HEAD" -Value 'changed'
        & $FreeDataKey -Repository $clone | Should -Be (& $FreeDataKey -Repository (New-Clone))
    }
}
