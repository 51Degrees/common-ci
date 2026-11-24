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
            '51Degrees.csv', '51Degrees-Tac.zip', 'chargify.json', 'entitlement.json',
            'example-source.json') {
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

    It 'knows no CSV evidence file and no file that came only from an address' {
        $env:_51DEGREES_LICENSE_KEY = 'license'
        foreach ($asset in 'evidence.csv', '51Degrees-EnterpriseIpiV41-AllProperties.ipi') {
            { Invoke-KeyStep $asset } | Should -Throw "*Unknown asset: $asset*"
            Remove-Item -Recurse -Force $script:Work
        }
    }
}

Describe 'actions/fetch-assets' {
    BeforeAll {
        $script:Action = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'actions' 'fetch-assets' 'action.yml')
    }

    It 'takes no key or address as an input, apart from the cache encryption key' {
        $script:Action -replace '(?m)^  encryption-key:', '' |
            Should -Not -Match '-(key|url):' -Because 'the license comes from the job environment as _51DEGREES_LICENSE_KEY'
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

    It 'saves and restores the asset-cache folder, after it is encrypted' {
        $script:Action | Should -Not -Match '(?m)^\s+path: assets\s*$'
        @([regex]::Matches($script:Action, '(?m)^\s+path: asset-cache\s*$')).Count | Should -Be 2
        $script:Action | Should -Match "(?s)- name: Encrypt assets.*- name: Save cache\s+if: \$\{\{ steps\.encrypt-assets\.outputs\.ready == 'true' \}\}"
        $script:Action | Should -Match '(?s)- name: Restore cache.*- name: Decrypt assets.*- name: Fetch assets'
    }

    It 'passes the step only the assets' {
        $script:Action | Should -Match 'fetch-assets\.ps1" -Assets \(\$env:_51DEGREES_ASSETS\.Trim\(\) -split "`n"\)\r?\n'
    }
}

Describe 'fetch-assets.ps1 with bulkdata' {

    # Bulkdata is replaced by stand-ins: the Available index lists two days,
    # and a download writes a JSON object naming the URL it was given, or
    # an empty file for the newest day when told to.
    BeforeEach {
        $global:FetchAssetsTest.Urls = [Collections.Generic.List[string]]::new()
        $global:FetchAssetsTest.EmptyNewest = $false
        function global:Invoke-WebRequest ([string]$Uri) {
            $global:FetchAssetsTest.Urls.Add($Uri)
            '{"2026/11/10":"2026-11-10T06:00:00.000","2026/11/11":"2026-11-11T06:00:00.000"}'
        }
        function global:curl {
            $url = $args[-1]
            $output = $args[$args.IndexOf('-fLo') + 1]
            $global:FetchAssetsTest.Urls.Add($url)
            if ($global:FetchAssetsTest.EmptyNewest -and $url.EndsWith('2026-11-11')) {
                Set-Content -Path $output -Value ''
            } else {
                Set-Content -Path $output -Value (@{ url = $url } | ConvertTo-Json -Compress)
            }
        }
        $global:FetchAssetsTest.Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-work-$(New-Guid)"
        New-Item -ItemType Directory -Path $global:FetchAssetsTest.Work | Out-Null
    }

    AfterEach {
        Remove-Item -Path Function:\Invoke-WebRequest, Function:\curl -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $global:FetchAssetsTest.Work -ErrorAction SilentlyContinue
    }

    BeforeAll {
        # Runs the step for $Asset in the stand-in work folder, with the
        # license key in the environment as the shared workflows export it.
        function Invoke-BulkStep ([string]$Asset) {
            $before = $env:_51DEGREES_LICENSE_KEY
            $env:_51DEGREES_LICENSE_KEY = 'KEY'
            Push-Location $global:FetchAssetsTest.Work
            try {
                & $script:Step -Assets $Asset 3>$null
            } finally {
                Pop-Location
                $env:_51DEGREES_LICENSE_KEY = $before
            }
        }
    }

    It 'gets <Asset> as the <Source> data source, newest day first' -ForEach @(
        @{ Asset = 'example-source.json'; Source = 'example-source' }
        @{ Asset = 'chargify.json'; Source = 'chargify' }
        @{ Asset = 'entitlement.json'; Source = 'entitlement' }
        @{ Asset = 'source-2.json'; Source = 'source-2' }
    ) {
        Invoke-BulkStep $Asset
        $file = Get-Content -Raw "$($global:FetchAssetsTest.Work)/assets/$Asset" | ConvertFrom-Json
        $file.url | Should -Be "https://bulkdata.51degrees.com/api/v4/Download/Production/$Source/KEY/2026-11-11"
        $global:FetchAssetsTest.Urls[0] | Should -BeLike "https://bulkdata.51degrees.com/api/v4/Available/Production/$Source/KEY/*"
    }

    It 'falls back to the day before when the newest file is empty' {
        $global:FetchAssetsTest.EmptyNewest = $true
        Invoke-BulkStep 'example-source.json'
        $file = Get-Content -Raw "$($global:FetchAssetsTest.Work)/assets/example-source.json" | ConvertFrom-Json
        $file.url | Should -BeLike '*/example-source/KEY/2026-11-10'
    }

    It 'refuses <Asset>, which is no data source name' -ForEach @(
        @{ Asset = 'unknown.bin' }
        @{ Asset = 'Upper.json' }
        @{ Asset = '../escape.json' }
        @{ Asset = 'two words.json' }
    ) {
        { Invoke-BulkStep $Asset } | Should -Throw -ExpectedMessage "*Unknown asset: $Asset*"
        $global:FetchAssetsTest.Urls.Count | Should -Be 0
    }
}
