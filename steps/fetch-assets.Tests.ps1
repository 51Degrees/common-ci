# Tests for steps/fetch-assets.ps1, covering the files it gets from the data
# repository. Run with: Invoke-Pester ./steps/fetch-assets.Tests.ps1
#
# `git` is replaced by a function that copies a stand-in data repository, whose
# get-data-files.ps1 fails a set number of times before it downloads, so no
# test reaches GitHub or the Distributor.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'fetch-assets.ps1'
    $repository = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-tests-$(New-Guid)"
    New-Item -ItemType Directory -Force -Path "$repository/device-detection",
        "$repository/ip-intelligence" | Out-Null
    Set-Content -Path "$repository/device-detection/51Degrees-LiteV4.1.hash.link" `
        -Value 'https://example.com/lite'
    Set-Content -Path "$repository/ip-intelligence/evidence.yml" -Value 'evidence'
    Set-Content -Path "$repository/get-data-files.ps1" -Value @'
param([string[]]$Name)
$test = $global:FetchAssetsTest
$test.Calls++
if ($test.Calls -le $test.Failures) { exit 1 }
foreach ($file in $Name) {
    # A file that is already there is kept, as the real script keeps it.
    $path = Join-Path $PSScriptRoot "device-detection/$file"
    if (-not (Test-Path -LiteralPath $path)) { Set-Content -Path $path -Value 'downloaded' }
}
'@

    # Global, because the step calls `git` and the stand-in script from its
    # own script scope.
    $global:FetchAssetsTest = @{ Repository = $repository }

    # Refuses a folder that is already there, as git does, and counts clones.
    function git {
        if ($args[0] -ne 'clone') { throw "Unexpected call: git $args" }
        if (Test-Path -LiteralPath $args[-1]) { throw "git clone: $($args[-1]) already exists" }
        Copy-Item -Recurse -Path $global:FetchAssetsTest.Repository -Destination $args[-1]
        New-Item -ItemType Directory -Path (Join-Path $args[-1] '.git') | Out-Null
        $global:FetchAssetsTest.Clones++
    }

    function Start-Sleep {}

    # Runs the step in a new folder, as a new GitHub Actions job whose
    # temporary folder is inside it, unless -SameJob runs it again in the last
    # one. The test reads the folder afterwards even when the step throws.
    function Invoke-Step ([string]$Asset, [int]$Failures, [switch]$SameJob) {
        $test = $global:FetchAssetsTest
        $test.Calls = 0
        $test.Failures = $Failures
        if (-not $SameJob) {
            $test.Clones = 0
            $test.Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-work-$(New-Guid)"
            New-Item -ItemType Directory -Path "$($test.Work)/runner-temp" | Out-Null
        }
        Push-Location $test.Work
        $runnerTemp = $env:RUNNER_TEMP
        $env:RUNNER_TEMP = "$($test.Work)/runner-temp"
        try {
            & $script:Step -Assets $Asset
        } finally {
            $env:RUNNER_TEMP = $runnerTemp
            Pop-Location
        }
    }
}

AfterAll {
    Remove-Item -Recurse -Force $global:FetchAssetsTest.Repository -ErrorAction SilentlyContinue
    Remove-Variable -Name FetchAssetsTest -Scope Global -ErrorAction SilentlyContinue
}

Describe 'fetch-assets.ps1 with the data repository' {

    # A step that throws leaves its clone behind, and every test runs in this
    # process, so the clone is removed with the test's folder.
    AfterEach {
        Remove-Item -Recurse -Force $global:FetchAssetsTest.Work -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force (Join-Path ([IO.Path]::GetTempPath()) "data-$PID") `
            -ErrorAction SilentlyContinue
    }

    It 'gets a linked file' {
        Invoke-Step -Asset '51Degrees-LiteV4.1.hash' -Failures 0
        Get-Content "$($global:FetchAssetsTest.Work)/assets/51Degrees-LiteV4.1.hash" |
            Should -Be 'downloaded'
        $global:FetchAssetsTest.Calls | Should -Be 1
    }

    It 'gets a linked file when the first download fails' {
        Invoke-Step -Asset '51Degrees-LiteV4.1.hash' -Failures 1
        Get-Content "$($global:FetchAssetsTest.Work)/assets/51Degrees-LiteV4.1.hash" |
            Should -Be 'downloaded'
        $global:FetchAssetsTest.Calls | Should -Be 2
    }

    It 'stops after three failed downloads and leaves no file' {
        { Invoke-Step -Asset '51Degrees-LiteV4.1.hash' -Failures 3 } |
            Should -Throw -ExpectedMessage '*did not download device-detection/51Degrees-LiteV4.1.hash*'
        $global:FetchAssetsTest.Calls | Should -Be 3
        "$($global:FetchAssetsTest.Work)/assets/51Degrees-LiteV4.1.hash" | Should -Not -Exist
    }

    It 'clones the data repository once in a job' {
        Invoke-Step -Asset '51Degrees-LiteV4.1.hash' -Failures 0
        Invoke-Step -Asset 'ip-intelligence-evidence.yml' -Failures 0 -SameJob
        $global:FetchAssetsTest.Clones | Should -Be 1
        "$($global:FetchAssetsTest.Work)/assets/ip-intelligence-evidence.yml" | Should -Exist
    }

    It 'keeps a file restored into the job''s clone' {
        Invoke-Step -Asset 'ip-intelligence-evidence.yml' -Failures 0
        $work = $global:FetchAssetsTest.Work
        Set-Content -Path "$work/runner-temp/51degrees-data/device-detection/51Degrees-LiteV4.1.hash" -Value 'restored'
        Invoke-Step -Asset '51Degrees-LiteV4.1.hash' -Failures 0 -SameJob
        Get-Content "$work/assets/51Degrees-LiteV4.1.hash" | Should -Be 'restored'
    }

    It 'removes its clone outside GitHub Actions' {
        $runnerTemp = $env:RUNNER_TEMP
        $env:RUNNER_TEMP = $null
        $work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-work-$(New-Guid)"
        $global:FetchAssetsTest.Work = $work
        $global:FetchAssetsTest.Calls = 0
        $global:FetchAssetsTest.Failures = 0
        New-Item -ItemType Directory -Path $work | Out-Null
        Push-Location $work
        try {
            & $script:Step -Assets 'ip-intelligence-evidence.yml'
        } finally {
            Pop-Location
            $env:RUNNER_TEMP = $runnerTemp
        }
        "$work/assets/ip-intelligence-evidence.yml" | Should -Exist
        Join-Path ([IO.Path]::GetTempPath()) "data-$PID" | Should -Not -Exist
    }

    It 'copies a file the repository holds without downloading' {
        Invoke-Step -Asset 'ip-intelligence-evidence.yml' -Failures 0
        Get-Content "$($global:FetchAssetsTest.Work)/assets/ip-intelligence-evidence.yml" |
            Should -Be 'evidence'
        $global:FetchAssetsTest.Calls | Should -Be 0
    }
}

Describe 'fetch-assets.ps1 and the license key' {
    # The step runs from a copy beside stand-ins for the two download scripts,
    # which record what they were asked for and write a small file, so no
    # test reaches the Distributor. The key reaches the step as the
    # _51DEGREES_LICENSE_KEY environment variable, as the shared workflows
    # export it.
    BeforeAll {
        $script:Folder = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-key-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:Folder | Out-Null
        Copy-Item -LiteralPath $script:Step -Destination $script:Folder
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'free-assets.psd1') -Destination $script:Folder
        Set-Content -Path (Join-Path $script:Folder 'fetch-hash-assets.ps1') -Value @'
param([string]$RepoName, [string]$DataType = 'HashV41', [string]$Product = 'V4TAC',
    [string]$ArchiveName = 'TAC-HashV41.hash.gz')
$global:FetchAssetsKeyTest.Calls.Add("hash $DataType $Product key=$env:_51DEGREES_LICENSE_KEY")
Set-Content -Path ($ArchiveName -replace '\.gz$', '') -Value 'downloaded'
'@
        Set-Content -Path (Join-Path $script:Folder 'download-data-file.ps1') -Value @'
param([string]$FullFilePath, [string]$DataType, [string]$Product)
$global:FetchAssetsKeyTest.Calls.Add("file $DataType $Product key=$env:_51DEGREES_LICENSE_KEY")
Set-Content -Path $FullFilePath -Value 'downloaded'
'@
        $script:KeyStep = Join-Path $script:Folder 'fetch-assets.ps1'

        function Invoke-KeyStep ([string]$Asset) {
            $global:FetchAssetsKeyTest = @{ Calls = [Collections.Generic.List[string]]::new() }
            $script:Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-key-work-$(New-Guid)"
            New-Item -ItemType Directory -Path $script:Work | Out-Null
            Push-Location $script:Work
            try {
                return (& $script:KeyStep -Assets $Asset 6>&1 | Out-String)
            } finally {
                Pop-Location
            }
        }
    }

    BeforeEach {
        $script:SavedKey = $env:_51DEGREES_LICENSE_KEY
        $env:_51DEGREES_LICENSE_KEY = $null
    }

    AfterEach {
        $env:_51DEGREES_LICENSE_KEY = $script:SavedKey
        Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:Folder -ErrorAction SilentlyContinue
        Remove-Variable -Name FetchAssetsKeyTest -Scope Global -ErrorAction SilentlyContinue
    }

    It 'downloads the device detection data file with _51DEGREES_LICENSE_KEY' {
        $env:_51DEGREES_LICENSE_KEY = 'license'
        Invoke-KeyStep 'TAC-HashV41.hash' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'hash HashV41 V4TAC key=license'
        "$script:Work/assets/TAC-HashV41.hash" | Should -Exist
    }

    It 'downloads the IP Intelligence data file from the Distributor, as IPIV41 and IPIV4Enterprise' {
        $env:_51DEGREES_LICENSE_KEY = 'license'
        Invoke-KeyStep '51Degrees-EnterpriseIpiV41.ipi' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'hash IPIV41 IPIV4Enterprise key=license'
    }

    It 'downloads the CSV file with _51DEGREES_LICENSE_KEY' {
        $env:_51DEGREES_LICENSE_KEY = 'license'
        Invoke-KeyStep '51Degrees-Tac.zip' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'file CSV V4TAC key=license'
    }

    It 'fails for each asset that needs a license when there is none, naming the variable' {
        foreach ($asset in 'TAC-HashV41.hash', '51Degrees-EnterpriseIpiV41.ipi',
            '51Degrees.csv', '51Degrees-Tac.zip') {
            { Invoke-KeyStep $asset } |
                Should -Throw "*'$asset' needs the data license key, and _51DEGREES_LICENSE_KEY is not set*"
            $global:FetchAssetsKeyTest.Calls | Should -BeNullOrEmpty
            "$script:Work/assets/$asset" | Should -Not -Exist
            Remove-Item -Recurse -Force $script:Work
        }
    }

    It 'takes no key or address as a parameter' {
        $parameters = (Get-Command $script:Step).Parameters.Keys
        $parameters | Should -Not -Contain 'LicenseKey'
        foreach ($name in $parameters) {
            $name | Should -Not -Match 'Key|Url|Detection|Intelligence' -Because 'the license comes only from _51DEGREES_LICENSE_KEY'
        }
    }

    It 'knows no CSV evidence file, no file that came only from an address and no JSON file' {
        $env:_51DEGREES_LICENSE_KEY = 'license'
        foreach ($asset in 'evidence.csv', '51Degrees-EnterpriseIpiV41-AllProperties.ipi',
            'example-source.json') {
            { Invoke-KeyStep $asset } | Should -Throw "*Unknown asset: $asset*"
            Remove-Item -Recurse -Force $script:Work
        }
    }

    It 'takes a JSON file for an unknown asset, not a licensed one, when there is no key' {
        { Invoke-KeyStep 'example-source.json' } | Should -Throw "*Unknown asset: example-source.json*"
        $global:FetchAssetsKeyTest.Calls | Should -BeNullOrEmpty
    }
}

Describe 'fetch-assets.ps1 and the CSV archive' {
    # The stand-in download writes an archive that holds the export for all
    # components beside the export for one component, as the Distributor's
    # archive does.
    BeforeAll {
        $script:CsvFolder = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-csv-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:CsvFolder | Out-Null
        Copy-Item -LiteralPath $script:Step -Destination $script:CsvFolder
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'free-assets.psd1') -Destination $script:CsvFolder
        Set-Content -Path (Join-Path $script:CsvFolder 'download-data-file.ps1') -Value @'
param([string]$FullFilePath, [string]$DataType, [string]$Product)
$content = Join-Path ([IO.Path]::GetTempPath()) "csv-content-$(New-Guid)"
New-Item -ItemType Directory -Path $content | Out-Null
Set-Content -Path "$content/51Degrees-Tac-All.csv" -Value 'ProfileId,HardwareVendor', '1,Vendor'
Set-Content -Path "$content/51Degrees-Tac-HardwarePlatform.csv" -Value 'ProfileId,HardwareVendor', '1,Vendor'
Compress-Archive -Path "$content/*" -DestinationPath $FullFilePath
Remove-Item -Recurse -Force -LiteralPath $content
'@
        $script:CsvStep = Join-Path $script:CsvFolder 'fetch-assets.ps1'
    }

    BeforeEach {
        $script:SavedKey = $env:_51DEGREES_LICENSE_KEY
        $env:_51DEGREES_LICENSE_KEY = 'license'
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-csv-work-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:Work | Out-Null
    }

    AfterEach {
        $env:_51DEGREES_LICENSE_KEY = $script:SavedKey
        Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:CsvFolder -ErrorAction SilentlyContinue
    }

    It 'keeps the header of the export for all components, and leaves no other file in the working folder<_>' -ForEach @('', ' with -FullCsv') {
        $full = $_ -ne ''
        Push-Location $script:Work
        try {
            & $script:CsvStep -Assets '51Degrees.csv' -FullCsv:$full 6>&1 | Out-Null
        } finally {
            Pop-Location
        }
        @(Get-ChildItem -LiteralPath $script:Work -Recurse -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($script:Work, $_.FullName) -replace '\\', '/' }) |
            Sort-Object | Should -Be @('assets', 'assets/51Degrees.csv')
        $expected = $full ? @('ProfileId,HardwareVendor', '1,Vendor') : @('ProfileId,HardwareVendor')
        Get-Content -LiteralPath "$script:Work/assets/51Degrees.csv" | Should -Be $expected
    }
}

Describe 'actions/fetch-assets' {
    BeforeAll {
        $script:Action = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'actions' 'fetch-assets' 'action.yml')
    }

    It 'takes no key or address as an input, apart from the cache encryption key and the key of a cache entry' {
        $script:Action -replace '(?m)^  (encryption|cache)-key:', '' |
            Should -Not -Match '-(key|url):' -Because 'the license comes from the job environment as _51DEGREES_LICENSE_KEY'
    }

    # The key it was given, or the one it worked out when the restore found
    # that entry or the step made one to save. Otherwise empty, so a later
    # job never restores an entry that was not saved.
    It 'gives the key of its cache entry as an output only when the entry exists' {
        $value = [regex]::Escape("value: `${{ inputs.cache-key || ((steps.cache-restore.outputs.cache-hit == 'true' || steps.confirm-save.outputs.cache-hit == 'true') && steps.hash-inputs.outputs.key) || '' }}")
        $script:Action | Should -Match "(?m)^outputs:\r?\n  cache-key:\r?\n(    #.*\r?\n)*    $value\r?$"
    }

    # The save step only warns when it fails, so the output takes the key
    # from a lookup of the entry after the save.
    It 'looks the saved entry up before giving its key' {
        $script:Action | Should -Match "(?s)- name: Save cache.*- name: Confirm the saved entry\s+id: confirm-save\s+if: \$\{\{ steps\.encrypt-assets\.outputs\.ready == 'true' \}\}\s+uses: actions/cache/restore@v5\s+with:\s+key: \$\{\{ steps\.hash-inputs\.outputs\.key \}\}"
        ($script:Action -split '- name: Confirm the saved entry', 2)[1] -split '(?m)^    - name: ' |
            Select-Object -First 1 | Should -Match 'lookup-only: true'
    }

    # A later job passes an earlier job's cache-key output back in, and then
    # takes every asset from that entry and downloads none.
    It 'given the key of a cache entry, restores that entry or fails, and never fetches or saves' {
        $steps = @{}
        foreach ($step in $script:Action -split '(?m)^    - name: ') {
            $steps[($step -split '\r?\n')[0].Trim()] = $step
        }
        $steps['Hash inputs'] | Should -Match "if: \$\{\{ inputs\.cache == 'true' && inputs\.cache-key == '' \}\}"
        $steps['Restore cache'] | Should -Match 'key: \$\{\{ inputs\.cache-key \|\| steps\.hash-inputs\.outputs\.key \}\}'
        $steps['Restore cache'] | Should -Match "lookup-only: \$\{\{ inputs\.lazy == 'true' && inputs\.cache-key == '' \}\}"
        $steps['Restore cache'] | Should -Match "fail-on-cache-miss: \$\{\{ inputs\.cache-key != '' \}\}"
        $steps['Decrypt assets'] | Should -Match "inputs\.cache-key != ''"
        $steps['Check the restored assets'] | Should -Match "if: \$\{\{ inputs\.cache-key != '' \}\}"
        $steps['Check the restored assets'] | Should -Match 'throw '
        $steps['Fetch assets'] | Should -Match "if: \$\{\{ inputs\.cache-key == '' && "
        $steps['Encrypt assets'] | Should -Match "inputs\.cache-key == '' && "
        $steps['List the cache entry'] | Should -Match "if: \$\{\{ inputs\.cache-key != '' && steps\.cache-restore\.outputs\.cache-hit == 'true' \}\}"
        $steps['Check the restored assets'] | Should -Match '_51DEGREES_ENTRY: \$\{\{ steps\.list-entry\.outputs\.held \}\}'
        $script:Action | Should -Match '(?s)- name: Restore cache.*- name: List the cache entry.*- name: Decrypt assets.*- name: Check the restored assets.*- name: Fetch assets'
    }

    It 'keys the cache on the assets and the cache input alone, never on the encryption key' {
        $hash = ($script:Action -split '- name: Restore cache')[0]
        $hash | Should -Not -Match 'toJSON\(inputs\)|inputs\.encryption-key'
    }

    It 'hands the encryption key only to the steps that encrypt and decrypt the cache' {
        foreach ($step in $script:Action -split '(?m)^    - name: ') {
            if ($step -notmatch 'inputs\.encryption-key') { continue }
            $step | Should -Match 'asset-cache\.ps1" -(Save|Restore)'
            $step | Should -Match 'CACHE_ENCRYPTION_KEY: \$\{\{ inputs\.encryption-key \}\}'
        }
    }

    # The restore, the save and the lookup that confirms the save.
    It 'saves and restores the asset-cache folder, after it is encrypted' {
        $script:Action | Should -Not -Match '(?m)^\s+path: assets\s*$'
        @([regex]::Matches($script:Action, '(?m)^\s+path: asset-cache\s*$')).Count | Should -Be 3
        $script:Action | Should -Match "(?s)- name: Encrypt assets.*- name: Save cache\s+if: \$\{\{ steps\.encrypt-assets\.outputs\.ready == 'true' \}\}"
        $script:Action | Should -Match '(?s)- name: Restore cache.*- name: Decrypt assets.*- name: Fetch assets'
    }

    It 'passes the step only the assets' {
        $script:Action | Should -Match 'fetch-assets\.ps1" -Assets \(\$env:_51DEGREES_ASSETS\.Trim\(\) -split "`n"\)\r?\n'
    }
}

# The scripts of the action's steps that check a restored entry, run as the
# runner runs them, in a folder of their own.
Describe 'actions/fetch-assets checking a restored cache entry' {
    BeforeAll {
        $script:ActionText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'actions' 'fetch-assets' 'action.yml')

        # The run block of the named step, without its indent.
        function Get-StepScript ([string]$Name) {
            $step = ($script:ActionText -split '(?m)^    - name: ') | Where-Object { $_.StartsWith($Name) }
            $lines = ($step -split '(?m)^      run: \|\r?\n', 2)[1] -split '\r?\n'
            $script = foreach ($line in $lines) {
                if ($line.Trim() -and -not $line.StartsWith('        ')) { break }
                if ($line.Length -ge 8) { $line.Substring(8) } else { '' }
            }
            $script -join "`n"
        }

        # Runs the named step's script in a new folder with these names in the
        # environment, after Setup has run there, and gives its output and
        # exit code.
        function Invoke-StepScript ([string]$Name, [hashtable]$Environment, [scriptblock]$Setup) {
            $work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-step-$(New-Guid)"
            New-Item -ItemType Directory -Path $work | Out-Null
            $file = Join-Path $work 'step.ps1'
            Set-Content -LiteralPath $file -Value (Get-StepScript $Name)
            $before = @{}
            foreach ($key in $Environment.Keys) {
                $before[$key] = [Environment]::GetEnvironmentVariable($key)
                [Environment]::SetEnvironmentVariable($key, $Environment[$key])
            }
            Push-Location $work
            try {
                if ($Setup) { & $Setup }
                $output = @(pwsh -NoProfile -NonInteractive -File $file 2>&1 | ForEach-Object { "$_" })
                [pscustomobject]@{ Output = $output -join "`n"; ExitCode = $LASTEXITCODE; Work = $work }
            } finally {
                Pop-Location
                foreach ($key in $before.Keys) {
                    [Environment]::SetEnvironmentVariable($key, $before[$key])
                }
            }
        }

        $script:Assets = "Free.hash`nPaid.ipi`n"
    }

    It 'lists the free files and the encrypted files the entry holds' {
        $outputFile = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-output-$(New-Guid)"
        $result = Invoke-StepScript 'List the cache entry' @{ GITHUB_OUTPUT = $outputFile } {
            New-Item -ItemType Directory -Path asset-cache | Out-Null
            Set-Content -LiteralPath asset-cache/Free.hash -Value 'free'
            Set-Content -LiteralPath asset-cache/Paid.ipi.enc -Value 'encrypted'
            Set-Content -LiteralPath asset-cache/encrypted.json -Value '{"Paid.ipi":"00"}'
        }
        $result.ExitCode | Should -Be 0
        Get-Content -Raw -LiteralPath $outputFile | Should -Be "held=[`"Free.hash`",`"Paid.ipi`"]$([Environment]::NewLine)"
        Remove-Item -Force -LiteralPath $outputFile
    }

    It 'passes when every asset was restored' {
        $result = Invoke-StepScript 'Check the restored assets' @{
            _51DEGREES_ASSETS = $script:Assets; _51DEGREES_CACHE = 'true'; _51DEGREES_ENTRY = '["Free.hash","Paid.ipi"]'
        } {
            New-Item -ItemType Directory -Path assets | Out-Null
            Set-Content -LiteralPath assets/Free.hash -Value 'free'
            Set-Content -LiteralPath assets/Paid.ipi -Value 'paid'
        }
        $result.ExitCode | Should -Be 0
    }

    It 'says the entry holds an asset encrypted when it was not decrypted' {
        $result = Invoke-StepScript 'Check the restored assets' @{
            _51DEGREES_ASSETS = $script:Assets; _51DEGREES_CACHE = 'true'; _51DEGREES_ENTRY = '["Free.hash","Paid.ipi"]'
        } {
            New-Item -ItemType Directory -Path assets | Out-Null
            Set-Content -LiteralPath assets/Free.hash -Value 'free'
        }
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match '::error::The asset cache entry holds Paid\.ipi encrypted, and they were not decrypted, because encryption-key was not given or is not the key'
        $result.Output | Should -Not -Match 'does not hold'
    }

    It 'says the entry does not hold an asset that it lacks' {
        $result = Invoke-StepScript 'Check the restored assets' @{
            _51DEGREES_ASSETS = $script:Assets; _51DEGREES_CACHE = 'true'; _51DEGREES_ENTRY = '["Free.hash"]'
        } {
            New-Item -ItemType Directory -Path assets | Out-Null
            Set-Content -LiteralPath assets/Free.hash -Value 'free'
        }
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match '::error::The asset cache entry does not hold Paid\.ipi\.'
        $result.Output | Should -Not -Match 'encrypted'
    }

    It 'fails when cache-key is given without cache' {
        $result = Invoke-StepScript 'Check the restored assets' @{
            _51DEGREES_ASSETS = $script:Assets; _51DEGREES_CACHE = ''; _51DEGREES_ENTRY = ''
        } {}
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'cache-key needs cache set to true'
    }
}
