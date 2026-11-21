# Tests for steps/publishing-secret-names.ps1, which gives the publishing and
# setup secrets the names the scripts ask for when a caller passes
# 'secrets: inherit', so the secrets arrive under their repository names.

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'publishing-secret-names.ps1'

    # The secrets as the workflows pass them: parsed from JSON, so the names
    # are matched with case.
    function ConvertTo-Keys ([hashtable]$Secrets) {
        return ($Secrets | ConvertTo-Json | ConvertFrom-Json -AsHashtable)
    }
}

Describe 'publishing-secret-names.ps1' {
    It 'gives each repository secret the name the scripts ask for' -ForEach @(
        @{ Repository = 'MAVEN_SETTINGS'; Asked = 'MavenSettings' }
        @{ Repository = 'JAVA_GPG_KEY_PASSPHRASE'; Asked = 'JavaGpgKeyPassphrase' }
        @{ Repository = 'JAVA_KEY_PGP_FILE'; Asked = 'JavaPGP' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_NAME'; Asked = 'CodeSigningKeyVaultName' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_URL'; Asked = 'CodeSigningKeyVaultUrl' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_CLIENT_ID'; Asked = 'CodeSigningKeyVaultClientId' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_TENANT_ID'; Asked = 'CodeSigningKeyVaultTenantId' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_CLIENT_SECRET'; Asked = 'CodeSigningKeyVaultClientSecret' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_CERTIFICATE_NAME'; Asked = 'CodeSigningKeyVaultCertificateName' }
        @{ Repository = 'CODE_SIGNING_KEY_VAULT_CERTIFICATE_DATA'; Asked = 'CodeSigningKeyVaultCertificateData' }
        @{ Repository = 'PYPI_TOKEN'; Asked = 'PypiToken' }
        @{ Repository = 'NGINX_PLUS_KEY'; Asked = 'NginxKey' }
        @{ Repository = 'NGINX_PLUS_CERT'; Asked = 'NginxCert' }
        @{ Repository = 'NGINX_PLUS_JWT_TOKEN'; Asked = 'NginxJwtToken' }
        @{ Repository = 'NPM_AUTH_TOKEN'; Asked = 'NPMAuthToken' }
        @{ Repository = 'NUGET_API_KEY'; Asked = 'ApiKey' }
        @{ Repository = 'STRONG_NAME_KEY_BASE64'; Asked = 'StrongNameKeyBase64' }
    ) {
        $keys = ConvertTo-Keys @{ $Repository = 'value' }
        & $script:Script -Keys $keys
        $keys[$Asked] | Should -Be 'value'
    }

    It 'leaves a value a caller passed under the asked name' {
        $keys = ConvertTo-Keys @{ PypiToken = 'mapped'; PYPI_TOKEN = 'inherited' }
        & $script:Script -Keys $keys
        $keys['PypiToken'] | Should -Be 'mapped'
    }

    It 'adds nothing when the repository secret is missing or empty' {
        $keys = ConvertTo-Keys @{ PYPI_TOKEN = '' }
        & $script:Script -Keys $keys
        $keys.ContainsKey('PypiToken') | Should -BeFalse
    }

    It 'gives no test key a name: those are read under their _51DEGREES_ names' {
        $keys = ConvertTo-Keys @{ DEVICE_DETECTION_KEY = 'x'; _51DEGREES_RESOURCE_KEY_BESPOKE = 'y' }
        & $script:Script -Keys $keys
        $keys.Keys | Sort-Object | Should -Be @('_51DEGREES_RESOURCE_KEY_BESPOKE', 'DEVICE_DETECTION_KEY')
    }

    It 'logs names only, never a value' {
        $keys = ConvertTo-Keys @{ NPM_AUTH_TOKEN = 'secret-value-123' }
        $log = & $script:Script -Keys $keys 6>&1 | Out-String
        $log | Should -Match 'NPMAuthToken from NPM_AUTH_TOKEN'
        $log | Should -Not -Match 'secret-value-123'
    }
}

Describe 'Where the shared scripts name the publishing secrets' {
    It 'names them before the keys become options in <_>' -ForEach @(
        'nightly-publish.prebuild.ps1', 'nightly-publish.build.ps1', 'nightly-publish.test.ps1',
        'nightly-publish.package.ps1', 'nightly-pull-request.build-and-test.ps1') {
        $lines = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' $_)
        $names = ($lines | Select-String -SimpleMatch 'steps/publishing-secret-names.ps1' |
                Select-Object -First 1).LineNumber
        $expand = ($lines | Select-String -SimpleMatch '$Options += $Options.Keys' |
                Select-Object -First 1).LineNumber
        $names | Should -Not -BeNullOrEmpty
        $names | Should -BeLessThan $expand
    }
}
