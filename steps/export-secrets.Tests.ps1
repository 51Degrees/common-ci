# Tests for steps/export-secrets.ps1. Run with: Invoke-Pester ./steps/export-secrets.Tests.ps1
#
# The step takes the job's secrets and variables as JSON and exports into the
# environment, each under its own name, every secret and every variable whose
# name starts with _51DEGREES_ and the secrets that only CI uses, which
# ci-secrets.psd1 lists, and nothing else. A name listed under Publish is
# exported only with -Publish, and one listed under Sign only with -Sign. A
# name that is both a secret and a variable is an error. The tests run it in
# this process, so each test clears the variables it set, and point GITHUB_ENV
# at a file of their own.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'export-secrets.ps1'
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Ci = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'ci-secrets.psd1')

    # Stand-in values. None is a real secret, and each is distinctive so that a
    # test can tell a value from a name.
    $script:Given = [ordered]@{
        _51DEGREES_RESOURCE_KEY_BESPOKE = 'value-resource-key-7f3a'
        _51DEGREES_LICENSE_KEY = 'value-license-key-2c9e'
        _51DEGREES_RESOURCE_KEY_51DID = 'value-51did-key-b41d'
        CODE_SIGNING_KEY_VAULT_URL = 'value-vault-url-e5d0'
        JAVA_KEY_PGP_FILE = "-----BEGIN PGP-----`nline-one-9a8b`nline-two-1c2d`n-----END PGP-----"
        NPM_AUTH_TOKEN = 'value-npm-token-4e6f'
        NUGET_API_KEY = 'value-nuget-key-8d2b'
        PUBLISH_ACCESS_TOKEN = 'value-publish-token-2a7c'
        _51DEGREES_NOT_PUBLISH_OR_SIGN = 'value-neither-class-6c1a'
        CI_ACCESS_TOKEN = 'value-access-token-0b1c'
        OTHER_TOKEN = 'value-other-token-3d4e'
        github_token = 'value-github-token-5f60'
        SOME_OTHER_NAME = 'value-other-name-7a8b'
    }
    $script:Json = $script:Given | ConvertTo-Json -Compress
    $script:Listed = @($script:Ci.Every) + @($script:Ci.Publish) + @($script:Ci.Sign)
    $script:Exported = @($script:Given.Keys | Where-Object { $_ -clike '_51DEGREES_*' -or $_ -cin $script:Listed })
    $script:Publishing = @($script:Exported | Where-Object { $_ -cin $script:Ci.Publish })
    $script:Signing = @($script:Exported | Where-Object { $_ -cin $script:Ci.Sign })
    $script:Unclassed = @($script:Exported | Where-Object { $_ -cnotin $script:Publishing -and $_ -cnotin $script:Signing })

    # Stand-in variables, none a real address.
    $script:GivenVars = [ordered]@{
        _51DEGREES_CLOUD_ENDPOINT = 'value-cloud-endpoint-9e1f'
        _51DEGREES_WEEKLY_RELEASES_FROM = 'value-weekly-from-3b5c'
        OTHER_VARIABLE = 'value-other-variable-6d2a'
    }
    $script:VarsJson = $script:GivenVars | ConvertTo-Json -Compress
    $script:ExportedVars = @($script:GivenVars.Keys | Where-Object { $_ -clike '_51DEGREES_*' })

    # The names GITHUB_ENV holds, in the order written, each with its value.
    # The runner's file takes name=value for one line and name<<delimiter,
    # the lines, then the delimiter for several.
    function Read-GitHubEnv ([string]$Path) {
        $result = [ordered]@{}
        $lines = @(Get-Content -LiteralPath $Path)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^([^=<]+)<<(.+)$') {
                $name, $delimiter = $Matches[1], $Matches[2]
                $value = @()
                for ($i++; $lines[$i] -ne $delimiter; $i++) { $value += $lines[$i] }
                $result[$name] = $value -join "`n"
            }
            elseif ($lines[$i] -match '^([^=]+)=(.*)$') {
                $result[$Matches[1]] = $Matches[2]
            }
        }
        return $result
    }

    # Runs the step with the secrets and the variables given, no variables
    # when none are given, as a job that publishes and signs unless told
    # otherwise. Every stream, so that the output check sees all the step
    # writes.
    function Invoke-Step ([string]$Json, [string]$Vars = '{}', [bool]$Publish = $true, [bool]$Sign = $true) {
        return (& $script:Step -Secrets $Json -Vars $Vars -Publish:$Publish -Sign:$Sign *>&1 | Out-String)
    }

    # The steps of a workflow or action file as a list of texts. A step
    # starts at '- name:' or '- uses:' at any indentation.
    function Get-FileSteps ([string]$Path) {
        $steps = @()
        $current = $null
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -cmatch '^\s*- (name|uses|id|if|run|env|with|shell):') {
                if ($null -ne $current) { $steps += $current }
                $current = ''
            }
            if ($null -ne $current) { $current += "$line`n" }
        }
        if ($null -ne $current) { $steps += $current }
        return $steps
    }
}

Describe 'export-secrets.ps1' {

    BeforeEach {
        $script:GitHubEnv = Join-Path ([IO.Path]::GetTempPath()) "export-secrets-tests-$(New-Guid).env"
        New-Item -ItemType File -Path $script:GitHubEnv | Out-Null
        $script:SavedGitHubEnv = $env:GITHUB_ENV
        $env:GITHUB_ENV = $script:GitHubEnv
    }

    AfterEach {
        $env:GITHUB_ENV = $script:SavedGitHubEnv
        Remove-Item -Force $script:GitHubEnv -ErrorAction SilentlyContinue
        foreach ($name in @($script:Given.Keys) + @($script:GivenVars.Keys)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    It 'exports every _51DEGREES_ secret and every listed CI secret under its own name' {
        Invoke-Step -Json $script:Json | Out-Null
        foreach ($name in $script:Exported) {
            (Get-Item -Path "Env:$name").Value | Should -Be $script:Given[$name] -Because "$name is a _51DEGREES_ secret or a listed CI secret"
        }
    }

    It 'exports nothing else' {
        Invoke-Step -Json $script:Json | Out-Null
        foreach ($name in $script:Given.Keys) {
            if ($name -cin $script:Exported) { continue }
            Test-Path -Path "Env:$name" | Should -BeFalse -Because "$name is neither a _51DEGREES_ secret nor a listed CI secret"
        }
    }

    It 'exports the automation token to a job that neither publishes nor signs' {
        Invoke-Step -Json $script:Json -Publish $false -Sign $false | Out-Null
        (Get-Item -Path 'Env:CI_ACCESS_TOKEN').Value | Should -Be $script:Given['CI_ACCESS_TOKEN']
    }

    It 'writes exactly the exported names to GITHUB_ENV, with their values, a multi-line value whole' {
        Invoke-Step -Json $script:Json | Out-Null
        $written = Read-GitHubEnv $script:GitHubEnv
        @($written.Keys | Sort-Object) | Should -Be @($script:Exported | Sort-Object)
        foreach ($name in $script:Exported) {
            $written[$name] | Should -Be $script:Given[$name]
        }
    }

    It 'writes only names to its output' {
        $output = Invoke-Step -Json $script:Json
        foreach ($name in $script:Given.Keys) {
            foreach ($line in ($script:Given[$name] -split "`n")) {
                $output | Should -Not -Match ([regex]::Escape($line)) -Because "the output holds names alone"
            }
        }
        foreach ($name in $script:Exported) {
            $output | Should -Match ([regex]::Escape($name))
        }
    }

    It 'renames nothing and fills nothing from another name' {
        Invoke-Step -Json $script:Json | Out-Null
        $written = Read-GitHubEnv $script:GitHubEnv
        @($written.Keys | Sort-Object) | Should -Be @($script:Exported | Sort-Object)
        foreach ($name in $written.Keys) {
            $written[$name] | Should -Be $script:Given[$name] -Because "$name holds its own secret's value"
        }
    }

    It 'skips a secret with no value' {
        $json = @{ _51DEGREES_RESOURCE_KEY_BESPOKE = ''; _51DEGREES_LICENSE_KEY = 'value-license-key-2c9e' } | ConvertTo-Json -Compress
        Invoke-Step -Json $json | Out-Null
        Test-Path -Path 'Env:_51DEGREES_RESOURCE_KEY_BESPOKE' | Should -BeFalse
        (Get-Item -Path 'Env:_51DEGREES_LICENSE_KEY').Value | Should -Be 'value-license-key-2c9e'
    }

    It 'does nothing with no secrets' {
        { Invoke-Step -Json '{}' | Out-Null } | Should -Not -Throw
        (Get-Content -LiteralPath $script:GitHubEnv) | Should -BeNullOrEmpty
    }

    It 'sets the process environment without GITHUB_ENV' {
        $env:GITHUB_ENV = $null
        Invoke-Step -Json $script:Json | Out-Null
        (Get-Item -Path 'Env:_51DEGREES_LICENSE_KEY').Value | Should -Be $script:Given['_51DEGREES_LICENSE_KEY']
    }

    Context 'publishing and signing names' {

        BeforeAll {
            # The names a run left, which the process environment and
            # GITHUB_ENV must agree on.
            function Get-Left {
                $written = Read-GitHubEnv $script:GitHubEnv
                $inProcess = @($script:Given.Keys | Where-Object { Test-Path -Path "Env:$_" } | Sort-Object)
                @($written.Keys | Sort-Object) | Should -Be $inProcess -Because "GITHUB_ENV and the process hold the same names"
                return $inProcess
            }
        }

        It 'exports no publishing or signing name without a switch' {
            $output = Invoke-Step -Json $script:Json -Publish $false -Sign $false
            Get-Left | Should -Be @($script:Unclassed | Sort-Object)
            foreach ($name in $script:Publishing + $script:Signing) {
                $output | Should -Not -Match ([regex]::Escape($name)) -Because "$name is not exported"
            }
        }

        It 'exports the publishing names and no signing name with -Publish' {
            Invoke-Step -Json $script:Json -Publish $true -Sign $false | Out-Null
            Get-Left | Should -Be @($script:Unclassed + $script:Publishing | Sort-Object)
        }

        It 'exports the signing names and no publishing name with -Sign' {
            Invoke-Step -Json $script:Json -Publish $false -Sign $true | Out-Null
            Get-Left | Should -Be @($script:Unclassed + $script:Signing | Sort-Object)
        }

        It 'exports both with both switches' {
            Invoke-Step -Json $script:Json -Publish $true -Sign $true | Out-Null
            Get-Left | Should -Be @($script:Exported | Sort-Object)
        }

        It 'takes the class from the lists alone, not from the start of the name' {
            Invoke-Step -Json $script:Json -Publish $false -Sign $false | Out-Null
            (Get-Item -Path 'Env:_51DEGREES_NOT_PUBLISH_OR_SIGN').Value | Should -Be $script:Given['_51DEGREES_NOT_PUBLISH_OR_SIGN']
        }

        It 'treats a variable as it treats a secret' {
            $vars = [ordered]@{
                MAVEN_SETTINGS = 'value-maven-settings-1a2b'
                CODE_SIGNING_KEY_VAULT_NAME = 'value-vault-name-3c4d'
                _51DEGREES_CLOUD_ENDPOINT = 'value-cloud-endpoint-9e1f'
            }
            try {
                Invoke-Step -Json '{}' -Vars ($vars | ConvertTo-Json -Compress) -Publish $false -Sign $true | Out-Null
                Test-Path -Path 'Env:MAVEN_SETTINGS' | Should -BeFalse
                (Get-Item -Path 'Env:CODE_SIGNING_KEY_VAULT_NAME').Value | Should -Be 'value-vault-name-3c4d'
                (Get-Item -Path 'Env:_51DEGREES_CLOUD_ENDPOINT').Value | Should -Be 'value-cloud-endpoint-9e1f'
            } finally {
                foreach ($name in $vars.Keys) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'variables' {

        It 'exports every _51DEGREES_ variable under its own name, with the secrets' {
            Invoke-Step -Json $script:Json -Vars $script:VarsJson | Out-Null
            foreach ($name in $script:ExportedVars) {
                (Get-Item -Path "Env:$name").Value | Should -Be $script:GivenVars[$name] -Because "$name is a _51DEGREES_ variable"
            }
            foreach ($name in $script:Exported) {
                (Get-Item -Path "Env:$name").Value | Should -Be $script:Given[$name] -Because "$name is a _51DEGREES_ secret"
            }
            $written = Read-GitHubEnv $script:GitHubEnv
            @($written.Keys | Sort-Object) | Should -Be @(@($script:Exported) + @($script:ExportedVars) | Sort-Object)
            foreach ($name in $script:ExportedVars) {
                $written[$name] | Should -Be $script:GivenVars[$name]
            }
        }

        It 'exports no variable that is neither a _51DEGREES_ name nor a listed one' {
            Invoke-Step -Json $script:Json -Vars $script:VarsJson | Out-Null
            foreach ($name in $script:GivenVars.Keys) {
                if ($name -cin $script:ExportedVars) { continue }
                Test-Path -Path "Env:$name" | Should -BeFalse -Because "$name is neither a _51DEGREES_ name nor a listed one"
            }
            $written = Read-GitHubEnv $script:GitHubEnv
            foreach ($name in $script:GivenVars.Keys) {
                if ($name -cin $script:ExportedVars) { continue }
                $written.Contains($name) | Should -BeFalse -Because "$name is neither a _51DEGREES_ name nor a listed one"
            }
        }

        It 'fails naming a name that is both a secret and a variable, and exports nothing' {
            # One name holds one thing. The step fails before it exports, names
            # the clash, and shows no value.
            $vars = [ordered]@{
                _51DEGREES_LICENSE_KEY = 'value-variable-license-5a6b'
                _51DEGREES_CLOUD_ENDPOINT = 'value-cloud-endpoint-9e1f'
            } | ConvertTo-Json -Compress
            $failure = $null
            try { & $script:Step -Secrets $script:Json -Vars $vars -Publish -Sign *>&1 | Out-Null }
            catch { $failure = $_ }
            $failure | Should -Not -BeNullOrEmpty -Because "a name that is both a secret and a variable is an error"
            $failure.Exception.Message | Should -Match '_51DEGREES_LICENSE_KEY'
            $failure.Exception.Message | Should -Not -Match 'value-'
            foreach ($name in @($script:Given.Keys) + @('_51DEGREES_CLOUD_ENDPOINT')) {
                Test-Path -Path "Env:$name" | Should -BeFalse -Because "nothing is exported on a clash"
            }
            (Get-Content -LiteralPath $script:GitHubEnv) | Should -BeNullOrEmpty
        }

        It 'fails on such a name in a class the job does not take' {
            $secrets = @{ NPM_AUTH_TOKEN = 'value-npm-token-4e6f' } | ConvertTo-Json -Compress
            $vars = @{ NPM_AUTH_TOKEN = 'value-variable-npm-2f7d' } | ConvertTo-Json -Compress
            { & $script:Step -Secrets $secrets -Vars $vars *>&1 | Out-Null } | Should -Throw '*NPM_AUTH_TOKEN*'
        }

        It 'writes only names to its output, no variable value' {
            $output = Invoke-Step -Json $script:Json -Vars $script:VarsJson
            foreach ($name in @($script:Given.Keys) + @($script:GivenVars.Keys)) {
                $value = if ($script:Given.Contains($name)) { $script:Given[$name] } else { $script:GivenVars[$name] }
                foreach ($line in ($value -split "`n")) {
                    $output | Should -Not -Match ([regex]::Escape($line)) -Because "the output holds names alone"
                }
            }
            foreach ($name in @($script:Exported) + @($script:ExportedVars)) {
                $output | Should -Match ([regex]::Escape($name))
            }
        }

        It 'skips a variable with no value' {
            $vars = @{ _51DEGREES_CLOUD_ENDPOINT = ''; _51DEGREES_WEEKLY_RELEASES_FROM = 'value-weekly-from-3b5c' } | ConvertTo-Json -Compress
            Invoke-Step -Json '{}' -Vars $vars | Out-Null
            Test-Path -Path 'Env:_51DEGREES_CLOUD_ENDPOINT' | Should -BeFalse
            (Get-Item -Path 'Env:_51DEGREES_WEEKLY_RELEASES_FROM').Value | Should -Be 'value-weekly-from-3b5c'
        }
    }
}

Describe 'Every place the step runs passes the variables with the secrets' {

    BeforeDiscovery {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $Files = @(Get-ChildItem (Join-Path $root '.github/workflows') -Filter '*.yml') +
            @(Get-ChildItem (Join-Path $root '.github/actions'), (Join-Path $root 'actions') -Recurse -Filter 'action.yml')
        $Files = @($Files | Where-Object { (Get-Content -Raw $_.FullName) -cmatch 'toJSON\(secrets\)|export-secrets\.ps1' })
    }

    It '<_.FullName> passes the variables wherever it passes the secrets' -ForEach $Files {
        $steps = @(Get-FileSteps $_.FullName)
        $steps.Count | Should -BeGreaterThan 0
        foreach ($step in $steps) {
            if ($step -cmatch 'toJSON\(secrets\)') {
                $step | Should -Match 'toJSON\(vars\)' -Because "a step that takes the secrets context takes the variables context too"
            }
            if ($step -cmatch 'export-secrets\.ps1') {
                $step | Should -Match '-Secrets ' -Because "the step takes the secrets"
                $step | Should -Match '-Vars ' -Because "the step takes the variables with the secrets"
            }
        }
    }
}
