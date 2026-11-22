# Tests for steps/set-resource-keys.ps1. Run with: Invoke-Pester ./steps/set-resource-keys.Tests.ps1
#
# The step takes the job's secrets as JSON and exports every secret whose name
# starts with _51DEGREES_ into the environment under its own name, and nothing
# else. The tests run it in this process, so each test clears the variables it
# set, and point GITHUB_ENV at a file of their own.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'set-resource-keys.ps1'

    # Stand-in values. None is a real secret, and each is distinctive so that a
    # test can tell a value from a name.
    $script:Given = [ordered]@{
        _51DEGREES_RESOURCE_KEY_BESPOKE = 'value-resource-key-7f3a'
        _51DEGREES_LICENSE_KEY = 'value-license-key-2c9e'
        _51DEGREES_RESOURCE_KEY_51DID = 'value-51did-key-b41d'
        _51DEGREES_CODE_SIGNING_KEY_VAULT_URL = 'value-vault-url-e5d0'
        _51DEGREES_JAVA_KEY_PGP_FILE = "-----BEGIN PGP-----`nline-one-9a8b`nline-two-1c2d`n-----END PGP-----"
        _51DEGREES_NPM_AUTH_TOKEN = 'value-npm-token-4e6f'
        _51DEGREES_ACCESS_TOKEN = 'value-access-token-0b1c'
        OTHER_TOKEN = 'value-other-token-3d4e'
        github_token = 'value-github-token-5f60'
        SOME_OTHER_NAME = 'value-other-name-7a8b'
    }
    $script:Json = $script:Given | ConvertTo-Json -Compress
    $script:Exported = @($script:Given.Keys | Where-Object { $_ -clike '_51DEGREES_*' })

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

    function Invoke-Step ([string]$Json) {
        # Every stream, so that the output check sees all the step writes.
        return (& $script:Step -Secrets $Json *>&1 | Out-String)
    }
}

Describe 'set-resource-keys.ps1' {

    BeforeEach {
        $script:GitHubEnv = Join-Path ([IO.Path]::GetTempPath()) "set-resource-keys-tests-$(New-Guid).env"
        New-Item -ItemType File -Path $script:GitHubEnv | Out-Null
        $script:SavedGitHubEnv = $env:GITHUB_ENV
        $env:GITHUB_ENV = $script:GitHubEnv
    }

    AfterEach {
        $env:GITHUB_ENV = $script:SavedGitHubEnv
        Remove-Item -Force $script:GitHubEnv -ErrorAction SilentlyContinue
        foreach ($name in $script:Given.Keys) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    It 'exports every _51DEGREES_ secret under its own name' {
        Invoke-Step -Json $script:Json | Out-Null
        foreach ($name in $script:Exported) {
            (Get-Item -Path "Env:$name").Value | Should -Be $script:Given[$name] -Because "$name is a _51DEGREES_ secret"
        }
    }

    It 'exports nothing else' {
        Invoke-Step -Json $script:Json | Out-Null
        foreach ($name in $script:Given.Keys) {
            if ($name -cin $script:Exported) { continue }
            Test-Path -Path "Env:$name" | Should -BeFalse -Because "$name is not a _51DEGREES_ secret"
        }
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
}