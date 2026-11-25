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
        & $PrefetchKey -FetchScript $FetchScript | Should -BeLike "$(Get-Date -Format FileDate)-*"
    }

    It 'is the same for the same asset list' {
        & $PrefetchKey -FetchScript $FetchScript | Should -Be (& $PrefetchKey -FetchScript $FetchScript)
    }

    It 'changes with the asset list' {
        $other = Join-Path $Work 'other-fetch-assets.ps1'
        Set-Content -Path $other -Value "./steps/fetch-assets.ps1 -Assets '51Degrees.csv'"
        & $PrefetchKey -FetchScript $FetchScript | Should -Not -Be (& $PrefetchKey -FetchScript $other)
    }

    It 'is all the action hashes, with no secret' {
        $hash = (Get-Content -Raw $Action) -split '- name: Check if cached' | Select-Object -First 1
        $hash | Should -Match 'prefetch-cache-key\.ps1'
        $hash | Should -Not -Match 'inputs\.secrets|inputs\.license-key'
    }
}

Describe 'free-data-cache-key.ps1' {

    It 'starts with the day' {
        & $FreeDataKey -Repository (New-Clone) | Should -BeLike "free-data-$(Get-Date -Format FileDate)-*"
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

Describe 'The free data files in prefetch_assets' {

    BeforeAll {
        $script:Text = Get-Content -Raw $Action
        function Get-Step ([string]$Name) {
            ($script:Text -split '(?m)^\s*- name: ') | Where-Object { $_.StartsWith($Name) }
        }
        function Get-CachePath ([string]$Step) {
            ($Step -split '(?m)^\s*path: \|\s*$', 2)[1] -split '\r?\n' |
                ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 2
        }
    }

    It 'restores and saves the same paths, without the clone''s .git folder' {
        $restore = Get-CachePath (Get-Step 'Restore the free data files')
        $save = Get-CachePath (Get-Step 'Cache the free data files')
        $restore | Should -Be $save
        $restore | Should -Be @('${{ runner.temp }}/51degrees-data/*', '!${{ runner.temp }}/51degrees-data/.git')
    }

    It 'saves only when the caller asks, from main' {
        $save = Get-Step 'Cache the free data files'
        $save | Should -Match "inputs\.save-free-data == 'true'"
        $save | Should -Match "github\.ref == 'refs/heads/main'"
    }

    It 'is saved by the publishing workflows alone' {
        $workflows = Get-ChildItem (Join-Path $PSScriptRoot '../.github/workflows') -Filter '*.yml'
        $saving = $workflows | Where-Object { (Get-Content -Raw $_.FullName) -match 'save-free-data:\s*true' } |
            ForEach-Object Name | Sort-Object
        $saving | Should -Be @('nightly-publish-main.yml', 'nightly-publish.yml')
    }
}

Describe 'The asset cache entry' {

    BeforeAll {
        $script:Workflows = Get-ChildItem (Join-Path $PSScriptRoot '../.github/workflows') -Filter '*.yml'
        $script:PullRequest = Get-Content -Raw (Join-Path $PSScriptRoot '../.github/workflows/nightly-pull-request.yml')
        $script:Configure = ($script:PullRequest -split '(?m)^  BuildAndTest:', 2)[0]
    }

    # The prefetch saves the entry, so only the publishing workflows run it.
    It 'is saved by the publishing workflows alone' {
        $saving = $script:Workflows | Where-Object { (Get-Content -Raw $_.FullName) -match 'prefetch_assets' } |
            ForEach-Object Name | Sort-Object
        $saving | Should -Be @('nightly-publish-main.yml', 'nightly-publish.yml')
    }

    # A pull request build works out the key the publishing workflows save
    # with and restores that entry. Its Configure job takes neither the cache
    # key nor the data file license.
    It 'is restored by the pull request build under the key the prefetch saves with' {
        $script:Configure | Should -Match 'steps/prefetch-cache-key\.ps1'
        $script:Configure | Should -Match 'ci/fetch-assets\.ps1'
        $script:Configure | Should -Match 'asset_cache_key: \$\{\{ steps\.hash-assets\.outputs\.key \}\}'
        $script:Configure | Should -Not -Match 'CACHE_ENCRYPTION_KEY|LICENSE_KEY_V4TAC_IPIV4ENTERPRISE|toJSON\(secrets\)'
    }
}
