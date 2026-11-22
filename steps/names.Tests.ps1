# Guards the names in this repository. Run with: Invoke-Pester ./steps/names.Tests.ps1
#
# Every secret the workflows read is a _51DEGREES_ name, passed by the caller
# with 'secrets: inherit', and the scripts read each from the environment under
# that name. No old or private name, no translation of one name to another and
# no list of the names other repositories read belongs in the tree. The checks
# are structural where they can be, and name the old forms only where a word
# is the only way to find them. This file is left out of its own checks.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Self = [IO.Path]::GetRelativePath($script:Root, $PSCommandPath) -replace '\\', '/'

    # The tracked text files, as paths relative to the root.
    $tracked = @(git -C $script:Root ls-files)
    $binary = '\.(png|jpg|jpeg|gif|ico|snk|zip|gz)$'
    $script:Files = @($tracked | Where-Object { $_ -notmatch $binary -and $_ -ne $script:Self })

    function Find-InFiles {
        param([string]$Pattern, [string[]]$Paths = $script:Files)
        $hits = @()
        foreach ($path in $Paths) {
            $lines = Get-Content -LiteralPath (Join-Path $script:Root $path)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -cmatch $Pattern) { $hits += "${path}:$($i + 1): $($lines[$i].Trim())" }
            }
        }
        return $hits
    }

    $script:Workflows = @($script:Files | Where-Object { $_ -like '.github/workflows/*.yml' })
    $script:Actions = @($script:Files | Where-Object { $_ -like '*/action.yml' })
    $script:Scripts = @($script:Files | Where-Object { $_ -like '*.ps1' })
}

Describe 'The names contract and the translation have left this repository' {

    It 'has no <path>' -ForEach @(
        @{ path = 'environment-variables.json' }
        @{ path = 'environment-variables.md' }
        @{ path = 'steps/environment-variables.ps1' }
        @{ path = 'steps/environment-variables.Tests.ps1' }

        @{ path = 'steps/publishing-secret-names.ps1' }
        @{ path = 'steps/fetch-csv-assets.ps1' }
    ) {
        $script:Files | Should -Not -Contain $path
    }

    It 'refers to none of them' {
        Find-InFiles 'environment-variables\.(json|md|ps1)|publishing-secret-names|fetch-csv-assets' |
            Should -BeNullOrEmpty
    }
}

Describe 'Workflows read secrets only under _51DEGREES_ names' {

    It 'reads every secret under a _51DEGREES_ name' {
        $hits = @()
        foreach ($path in $script:Workflows + $script:Actions) {
            $text = Get-Content -Raw -LiteralPath (Join-Path $script:Root $path)
            foreach ($match in [regex]::Matches($text, '(?<![\w-])secrets\.([A-Za-z0-9_.-]+)')) {
                $name = $match.Groups[1].Value
                if ($name -cnotlike '_51DEGREES_*' -and $name -cne 'GITHUB_TOKEN') { $hits += "${path}: secrets.$name" }
            }
        }
        $hits | Should -BeNullOrEmpty
    }

    It 'declares no secret of its own, so a caller passes secrets: inherit' {
        # A reusable workflow's own declaration sits at on.workflow_call.secrets,
        # four spaces in. A job's 'secrets: inherit' is not a declaration.
        Find-InFiles '^    secrets:\s*$' $script:Workflows | Should -BeNullOrEmpty
    }

    It 'passes no secret to a script by another name' {
        Find-InFiles '\$Keys\b|Options\.Keys|"Keys"|\[hashtable\]\$Keys' | Should -BeNullOrEmpty
    }
}

Describe 'No old or private name is in the tree' {

    # The old names of secrets, as the workflows declared them, the scripts
    # took them as parameters, and the environment variables they were copied
    # to. Each is a whole word, so a _51DEGREES_ name that ends in one of them
    # does not match.
    It 'holds none of the old secret names' {
        $old = @(
            'Test\w*ResourceKey', 'SuperResourceKey', 'TestLicenseKey', 'TestPypiToken', 'PypiToken'
            'NPMAuthToken', 'MavenSettings', 'JavaGpgKeyPassphrase', 'JavaPGP', 'StrongNameKeyBase64'
            'ResourceKeyCloudV5Bespoke', 'UsePublishTests', 'CsvUrl', 'DeviceDetectionUrl', 'IpIntelligenceUrl'
            'AcceptCH\w*Key', 'CodeSigningKeyVault\w*', 'Nginx(Key|Cert|JwtToken)'
            'Docker(User|Password|Registry|Container)', 'DataKey', 'DataUrl'
            'ACCESS_TOKEN', 'LABEL_SYNC_TOKEN', 'NUGET_API_KEY', 'PYPI_TOKEN', 'NPM_AUTH_TOKEN', 'MAVEN_SETTINGS'
            'CODE_SIGNING_\w+', 'STRONG_NAME_KEY_BASE64', 'JAVA_GPG_KEY_PASSPHRASE', 'JAVA_KEY_PGP_FILE'
            'NGINX_PLUS_\w+', 'DEVICE_DETECTION_KEY', 'IP_INTELLIGENCE_KEY', 'IPI_DATA_FILE_URL'
            'RESOURCE_KEY_CLOUD_V5_BESPOKE', 'SUPER_RESOURCE_KEY', 'ACCEPTCH_\w+', 'TEST_\w+_RESOURCE_KEY'
            'LICENSE_KEY_CLOUD_\w+', '_51DEGREES_UA_CSV', 'KEYVAULT_\w+'
        )
        Find-InFiles "\b($($old -join '|'))\b" | Should -BeNullOrEmpty
    }

    It 'passes no key, token or address as a script parameter under an old name' {
        Find-InFiles '[-$](DeviceDetection|IpIntelligence|ApiKey|LicenseKey)\b' $script:Scripts | Should -BeNullOrEmpty
    }

    It 'sets no old environment variable' {
        Find-InFiles '\$env:(resource_key|license_key|RESOURCEKEY|LICENSEKEY)\b' | Should -BeNullOrEmpty
    }

    It 'fetches no CSV evidence' {
        Find-InFiles '20000 User Agents\.csv' | Should -BeNullOrEmpty
    }
}
