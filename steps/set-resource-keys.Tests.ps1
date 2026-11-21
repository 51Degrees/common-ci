# Tests for steps/set-resource-keys.ps1, which exports the secrets the tests
# read as environment variables.
#
# Each test runs the script on a small list of agreed names in the test
# drive, with made-up secrets, and reads what it put in the environment, the
# GitHub environment file and the log. Every name the tests use holds
# SRKTEST, so nothing the runner already has is touched, and every such
# variable is removed before and after each test.

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'set-resource-keys.ps1'
    $script:RealList = Join-Path $PSScriptRoot '..' 'environment-variables.json'

    function New-Variable ([string]$Name, [string[]]$Deprecated = @(),
        [string]$FilledInCiFrom) {
        $variable = [ordered]@{
            name = $Name
            holds = 'A value for these tests.'
            readByPackages = $false
            languages = @('node')
            deprecated = @($Deprecated | ForEach-Object {
                    [ordered]@{ name = $_; languages = @('node'); stopsBeingReadIn = '' }
                })
        }
        if ($FilledInCiFrom) {
            $variable.filledInCiFrom = $FilledInCiFrom
        }
        return $variable
    }

    # Writes a list holding the given variables to the test drive and
    # returns its path.
    function New-List ($Variables) {
        $list = [ordered]@{
            description = 'A list for these tests.'
            languages = [ordered]@{
                node = [ordered]@{ name = 'Node.js'; repository = '51Degrees/51degrees-node' }
            }
            variables = @($Variables)
            otherNames = @()
        }
        $path = Join-Path $TestDrive 'environment-variables.json'
        $list | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        return $path
    }

    # Runs the script and returns its log as text. The secrets are passed
    # the way the workflow passes them: parsed from JSON, so the names are
    # matched with case.
    function Invoke-Script ([hashtable]$Secrets, [string]$ListPath) {
        $keys = $Secrets | ConvertTo-Json | ConvertFrom-Json -AsHashtable
        return (& $script:Script -Keys $keys -ListPath $ListPath 6>&1 |
                Out-String)
    }

    function Remove-TestVariables {
        Get-ChildItem Env: |
            Where-Object { $_.Name -like '*SRKTEST*' } |
            ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }
    }
}

Describe 'set-resource-keys.ps1' {
    BeforeEach {
        Remove-TestVariables
        $script:SavedGitHubEnv = $env:GITHUB_ENV
        $env:GITHUB_ENV = Join-Path $TestDrive 'github-env.txt'
        Set-Content -LiteralPath $env:GITHUB_ENV -Value $null
    }

    AfterEach {
        Remove-TestVariables
        $env:GITHUB_ENV = $script:SavedGitHubEnv
    }

    It 'still exports every secret whose name starts with the prefix' {
        $list = New-List @()
        Invoke-Script @{ _51DEGREES_RESOURCE_KEY_SRKTEST_A = 'value-a' } $list | Out-Null
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST_A | Should -Be 'value-a'
        Get-Content -LiteralPath $env:GITHUB_ENV |
            Should -Contain '_51DEGREES_RESOURCE_KEY_SRKTEST_A=value-a'
    }

    It 'exports the secret of every agreed name, whatever its prefix' {
        $list = New-List @(New-Variable '_51DEGREES_LICENSE_KEY_SRKTEST')
        Invoke-Script @{ _51DEGREES_LICENSE_KEY_SRKTEST = 'licence' } $list | Out-Null
        $env:_51DEGREES_LICENSE_KEY_SRKTEST | Should -Be 'licence'
    }

    It 'exports no secret that is neither an agreed name nor a resource key' {
        $list = New-List @()
        Invoke-Script @{ _51DEGREES_SRKTEST_UNLISTED = 'x'; SRKTEST_OTHER = 'y' } $list |
            Out-Null
        $env:_51DEGREES_SRKTEST_UNLISTED | Should -BeNullOrEmpty
        $env:SRKTEST_OTHER | Should -BeNullOrEmpty
    }

    It 'fills an agreed name that has no secret from the secret its entry names' {
        $list = New-List @(New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' `
                -FilledInCiFrom '_51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE')
        Invoke-Script @{ _51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE = 'source' } $list |
            Out-Null
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST | Should -Be 'source'
        Get-Content -LiteralPath $env:GITHUB_ENV |
            Should -Contain '_51DEGREES_RESOURCE_KEY_SRKTEST=source'
    }

    It 'fills only when the agreed name has no secret of its own' {
        $list = New-List @(New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' `
                -FilledInCiFrom '_51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE')
        Invoke-Script @{
            _51DEGREES_RESOURCE_KEY_SRKTEST = 'own'
            _51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE = 'source'
        } $list | Out-Null
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST | Should -Be 'own'
    }

    It 'leaves a value the job already set' {
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST = 'from-the-job'
        $list = New-List @(New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' `
                -FilledInCiFrom '_51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE')
        Invoke-Script @{ _51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE = 'source' } $list |
            Out-Null
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST | Should -Be 'from-the-job'
    }

    It 'never fills from an old name, even when only the old name has a secret' {
        $list = New-List @(New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' @('SRKTEST_OLD'))
        Invoke-Script @{ SRKTEST_OLD = 'old' } $list | Out-Null
        $env:_51DEGREES_RESOURCE_KEY_SRKTEST | Should -BeNullOrEmpty
    }

    It 'logs which name filled which, and never a value' {
        $list = New-List @(New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' `
                -FilledInCiFrom '_51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE')
        $log = Invoke-Script @{ _51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE = 'secret-value-123' } $list
        $log | Should -Match '_51DEGREES_RESOURCE_KEY_SRKTEST from _51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE'
        $log | Should -Not -Match 'secret-value-123'
    }

    It 'names each key that has no value, and does not fail' {
        $list = New-List @(
            New-Variable '_51DEGREES_RESOURCE_KEY_SRKTEST' `
                -FilledInCiFrom '_51DEGREES_RESOURCE_KEY_SRKTEST_SOURCE'
            New-Variable '_51DEGREES_LICENSE_KEY_SRKTEST'
            New-Variable '_51DEGREES_SRKTEST_NOT_A_KEY'
        )
        $log = Invoke-Script @{ SRKTEST_UNRELATED = 'x' } $list
        $log | Should -Match 'No value for _51DEGREES_RESOURCE_KEY_SRKTEST\b'
        $log | Should -Match 'No value for _51DEGREES_LICENSE_KEY_SRKTEST\b'
        $log | Should -Not -Match '_51DEGREES_SRKTEST_NOT_A_KEY'
    }
}

Describe 'The list in this repository' {
    BeforeAll {
        $script:List = Get-Content -Raw -LiteralPath $script:RealList | ConvertFrom-Json
        function Get-Entry ([string]$Name) {
            return $script:List.variables | Where-Object name -CEQ $Name
        }
    }

    It 'fills the resource keys from the _51DEGREES_ secrets that carry their properties' {
        (Get-Entry '_51DEGREES_RESOURCE_KEY').filledInCiFrom |
            Should -BeExactly '_51DEGREES_RESOURCE_KEY_BESPOKE'
        (Get-Entry '_51DEGREES_RESOURCE_KEY_SUPER').filledInCiFrom |
            Should -BeExactly '_51DEGREES_RESOURCE_KEY_BESPOKE'
        (Get-Entry '_51DEGREES_RESOURCE_KEY_BASIC').filledInCiFrom |
            Should -BeExactly '_51DEGREES_RESOURCE_KEY_FREE'
    }

    It 'fills the 51Did resource key from no other secret' {
        # The 51Did license key cannot read results made with the BESPOKE
        # key, so the 51Did key comes only from the secret of its own name.
        (Get-Entry '_51DEGREES_RESOURCE_KEY_51DID').PSObject.Properties['filledInCiFrom'] |
            Should -BeNullOrEmpty
    }

    It 'no longer lists a key for each Accept-CH header, a data file address or a duplicate' {
        # The Accept-CH tests use _51DEGREES_LICENSE_KEY_BESPOKE with values=
        # naming the one property each needs, and data files come from the
        # distributor with _51DEGREES_LICENSE_KEY.
        foreach ($name in '_51DEGREES_LICENSE_KEY_CLOUDV5BESPOKE',
            '_51DEGREES_RESOURCE_KEY_PLATFORM', '_51DEGREES_RESOURCE_KEY_HARDWARE',
            '_51DEGREES_RESOURCE_KEY_BROWSER', '_51DEGREES_RESOURCE_KEY_NO_SETHEADER',
            '_51DEGREES_RESOURCE_KEY_ACCEPTCH_BROWSER', '_51DEGREES_RESOURCE_KEY_ACCEPTCH_HARDWARE',
            '_51DEGREES_RESOURCE_KEY_ACCEPTCH_NONE', '_51DEGREES_RESOURCE_KEY_ACCEPTCH_PLATFORM',
            '_51DEGREES_IPI_DATA_FILE_URL') {
            Get-Entry $name | Should -BeNullOrEmpty -Because "$name is no longer agreed"
        }
    }

    It 'keeps the keys the tests read in their place' {
        Get-Entry '_51DEGREES_LICENSE_KEY_BESPOKE' | Should -Not -BeNullOrEmpty
        Get-Entry '_51DEGREES_LICENSE_KEY' | Should -Not -BeNullOrEmpty
    }
}

Describe 'The 51Did resource key, set from the list in this repository' {
    BeforeAll {
        $script:Did = '_51DEGREES_RESOURCE_KEY_51DID'
        $list = Get-Content -Raw -LiteralPath $script:RealList | ConvertFrom-Json
        # Every name the script may set from the real list, so each can be
        # cleared before a test and put back after it.
        $script:Touched = @(@($list.variables | ForEach-Object { [string]$_.name }) +
            '_51DEGREES_RESOURCE_KEY_BESPOKE' | Sort-Object -Unique)
    }

    BeforeEach {
        $script:Saved = @{}
        foreach ($name in $script:Touched) {
            $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $script:SavedGitHubEnv = $env:GITHUB_ENV
        $env:GITHUB_ENV = Join-Path $TestDrive 'github-env.txt'
        Set-Content -LiteralPath $env:GITHUB_ENV -Value $null
    }

    AfterEach {
        foreach ($name in $script:Touched) {
            [Environment]::SetEnvironmentVariable($name, $script:Saved[$name])
        }
        $env:GITHUB_ENV = $script:SavedGitHubEnv
    }

    It 'is not filled from the BESPOKE secret when it has no secret of its own' {
        Invoke-Script @{ _51DEGREES_RESOURCE_KEY_BESPOKE = 'srktest-bespoke' } $script:RealList |
            Out-Null
        [Environment]::GetEnvironmentVariable($script:Did) | Should -BeNullOrEmpty
    }

    It 'is set from the secret of its own name' {
        Invoke-Script @{
            _51DEGREES_RESOURCE_KEY_51DID = 'srktest-51did'
            _51DEGREES_RESOURCE_KEY_BESPOKE = 'srktest-bespoke'
        } $script:RealList | Out-Null
        [Environment]::GetEnvironmentVariable($script:Did) | Should -BeExactly 'srktest-51did'
    }

    It 'leaves out the 51Did license key, which only the Cloud 51Did workflows set' {
        # The 51Did license key reads only results made with the 51Did
        # resource key, so it is not put into every job. The other license
        # keys still are.
        $log = Invoke-Script @{
            _51DEGREES_LICENSE_KEY_51DID = 'srktest-license-51did'
            _51DEGREES_LICENSE_KEY_BESPOKE = 'srktest-license-bespoke'
        } $script:RealList
        [Environment]::GetEnvironmentVariable('_51DEGREES_LICENSE_KEY_51DID') |
            Should -BeNullOrEmpty
        Get-Content -LiteralPath $env:GITHUB_ENV |
            Should -Not -Contain '_51DEGREES_LICENSE_KEY_51DID=srktest-license-51did'
        [Environment]::GetEnvironmentVariable('_51DEGREES_LICENSE_KEY_BESPOKE') |
            Should -BeExactly 'srktest-license-bespoke'
        $log | Should -Not -Match 'srktest-license-51did'
    }
}

Describe 'Where the shared scripts export the keys' {
    # The keys must be in the environment before anything of the repository
    # runs: its own CI, its fetch-assets.ps1 (which reads
    # _51DEGREES_LICENSE_KEY) and its setup.
    It "runs before the repository's own scripts in <_>" -ForEach @(
        'nightly-pull-request.build-and-test.ps1', 'nightly-publish.test.ps1') {
        $lines = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' $_)
        $keys = ($lines | Select-String -SimpleMatch 'steps/set-resource-keys.ps1' |
                Select-Object -First 1).LineNumber
        $keys | Should -Not -BeNullOrEmpty
        foreach ($later in '$Options.CI', 'ci/fetch-assets.ps1', 'ci/setup-environment.ps1') {
            $line = ($lines | Select-String -SimpleMatch $later | Select-Object -First 1).LineNumber
            $keys | Should -BeLessThan $line -Because "the keys are needed by $later"
        }
    }

    It 'runs in the prefetch action before the repository fetches its assets' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' '.github' 'actions' 'prefetch_assets' 'action.yml')
        $keys = $text.IndexOf('steps/set-resource-keys.ps1')
        $keys | Should -BeGreaterThan 0
        $keys | Should -BeLessThan $text.IndexOf('& "$env:repo/ci/fetch-assets.ps1"')
    }
}
