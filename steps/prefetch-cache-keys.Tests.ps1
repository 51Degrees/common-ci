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
        function Get-ConfigureStep ([string]$Name) {
            ($script:Configure -split '(?m)^      - name: ') | Where-Object { $_.StartsWith($Name) }
        }
    }

    # The prefetch saves the entry, so it runs in the publishing workflows and
    # in the pull request build.
    It 'is saved by the publishing workflows and the pull request build alone' {
        $saving = $script:Workflows | Where-Object { (Get-Content -Raw $_.FullName) -match 'prefetch_assets' } |
            ForEach-Object Name | Sort-Object
        $saving | Should -Be @('nightly-publish-main.yml', 'nightly-publish.yml', 'nightly-pull-request.yml')
    }

    # A pull request's own run saves the entry where only that pull request
    # reads it, so the pull request build prefetches for that event alone.
    It 'is filled by a pull request''s own run when the day''s entry is missing' {
        $prefetch = Get-ConfigureStep 'Prefetch assets'
        $prefetch | Should -Match "if: inputs\.cache-assets && github\.event_name == 'pull_request'\r?\n"
        $prefetch | Should -Match 'uses: \./\.github/actions/prefetch_assets'
        $prefetch | Should -Match 'license-key: \$\{\{ secrets\.LICENSE_KEY_V4TAC_IPIV4ENTERPRISE \}\}'
        $prefetch | Should -Match 'encryption-key: \$\{\{ secrets\.CACHE_ENCRYPTION_KEY \}\}'
        $prefetch | Should -Not -Match 'save-free-data'
    }

    # Any other run of the pull request build, such as the nightly's on a
    # branch, works out the key the publishing workflows save with and
    # restores that entry, taking neither the cache key nor the data file
    # license.
    It 'is restored by the pull request build under the key the prefetch saves with' {
        $hash = Get-ConfigureStep 'Hash assets'
        $hash | Should -Match "if: inputs\.cache-assets && github\.event_name != 'pull_request'\r?\n"
        $hash | Should -Match 'steps/prefetch-cache-key\.ps1'
        $hash | Should -Match 'ci/fetch-assets\.ps1'
        $hash | Should -Not -Match 'CACHE_ENCRYPTION_KEY|LICENSE_KEY_V4TAC_IPIV4ENTERPRISE|toJSON\(secrets\)'
        $script:Configure | Should -Match 'asset_cache_key: \$\{\{ steps\.prefetch-assets\.outputs\.cache-key \|\| steps\.hash-assets\.outputs\.key \}\}'
    }

    # The publishing workflows' Test job checks out common-ci only for an
    # entry that tests the package, so only that entry has the script the
    # decrypting step runs.
    It 'is restored and decrypted in <_>''s Test job only by an entry that tests the package' -ForEach @(
        'nightly-publish.yml', 'nightly-publish-main.yml'
    ) {
        $text = Get-Content -Raw (Join-Path $PSScriptRoot "../.github/workflows/$_")
        $test = ($text -split '(?m)^  Test:', 2)[1]
        foreach ($name in 'Restore Asset Cache', 'Decrypt Asset Cache') {
            $step = ($test -split '(?m)^      - name: ') | Where-Object { $_.StartsWith($name) }
            $step | Should -Match 'if: \$\{\{ needs\.configure\.outputs\.asset_cache_key && matrix\.options\.packagerequirement \}\}\r?\n'
        }
    }
}
