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
    Set-Content -Path (Join-Path $PSScriptRoot "device-detection/$file") -Value 'downloaded'
}
'@

    # Global, because the step calls `git` and the stand-in script from its
    # own script scope.
    $global:FetchAssetsTest = @{ Repository = $repository }

    # Refuses a folder that is already there, as git does.
    function git {
        if ($args[0] -ne 'clone') { throw "Unexpected call: git $args" }
        if (Test-Path -LiteralPath $args[-1]) { throw "git clone: $($args[-1]) already exists" }
        Copy-Item -Recurse -Path $global:FetchAssetsTest.Repository -Destination $args[-1]
    }

    function Start-Sleep {}

    # Runs the step in a new folder, which the test reads afterwards even when
    # the step throws.
    function Invoke-Step ([string]$Asset, [int]$Failures) {
        $test = $global:FetchAssetsTest
        $test.Calls = 0
        $test.Failures = $Failures
        $test.Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-work-$(New-Guid)"
        New-Item -ItemType Directory -Path $test.Work | Out-Null
        Push-Location $test.Work
        try {
            & $script:Step -Assets $Asset
        } finally {
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

    It 'copies a file the repository holds without downloading' {
        Invoke-Step -Asset 'ip-intelligence-evidence.yml' -Failures 0
        Get-Content "$($global:FetchAssetsTest.Work)/assets/ip-intelligence-evidence.yml" |
            Should -Be 'evidence'
        $global:FetchAssetsTest.Calls | Should -Be 0
    }
}

Describe 'fetch-assets.ps1 and the licence key' {
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
param([string]$RepoName, [string]$LicenseKey, [string]$Url, [string]$DataType = 'HashV41',
    [string]$Product = 'V4TAC', [string]$ArchiveName = 'TAC-HashV41.hash.gz')
$global:FetchAssetsKeyTest.Calls.Add("hash $DataType $Product key=$LicenseKey url=$Url")
Set-Content -Path ($ArchiveName -replace '\.gz$', '') -Value 'downloaded'
'@
        Set-Content -Path (Join-Path $script:Folder 'download-data-file.ps1') -Value @'
param([string]$LicenseKey, [string]$DataType, [string]$Product, [string]$Url, [string]$FullFilePath)
$global:FetchAssetsKeyTest.Calls.Add("file $DataType $Product key=$LicenseKey url=$Url")
Set-Content -Path $FullFilePath -Value 'downloaded'
'@
        $script:KeyStep = Join-Path $script:Folder 'fetch-assets.ps1'

        function Invoke-KeyStep ([string]$Asset, [hashtable]$Arguments = @{}) {
            $global:FetchAssetsKeyTest = @{ Calls = [Collections.Generic.List[string]]::new() }
            $script:Work = Join-Path ([IO.Path]::GetTempPath()) "fetch-assets-key-work-$(New-Guid)"
            New-Item -ItemType Directory -Path $script:Work | Out-Null
            Push-Location $script:Work
            try {
                return (& $script:KeyStep -Assets $Asset @Arguments 6>&1 | Out-String)
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
        $env:_51DEGREES_LICENSE_KEY = 'licence'
        Invoke-KeyStep 'TAC-HashV41.hash' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'hash HashV41 V4TAC key=licence url='
        "$script:Work/assets/TAC-HashV41.hash" | Should -Exist
    }

    It 'downloads the IP Intelligence data file from the Distributor, as IPIV41 and IPIV4Enterprise' {
        $env:_51DEGREES_LICENSE_KEY = 'licence'
        Invoke-KeyStep '51Degrees-EnterpriseIpiV41.ipi' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'hash IPIV41 IPIV4Enterprise key=licence url='
    }

    It 'downloads the CSV file with _51DEGREES_LICENSE_KEY and no address' {
        $env:_51DEGREES_LICENSE_KEY = 'licence'
        Invoke-KeyStep '51Degrees-Tac.zip' | Out-Null
        $global:FetchAssetsKeyTest.Calls | Should -Be 'file CSV V4TAC key=licence url='
    }

    It 'fails for each asset that needs a licence when there is none, naming the variable' {
        foreach ($asset in 'TAC-HashV41.hash', '51Degrees-EnterpriseIpiV41.ipi',
            '51Degrees.csv', '51Degrees-Tac.zip', 'chargify.json', 'entitlement.json') {
            { Invoke-KeyStep $asset } |
                Should -Throw "*'$asset' needs the data licence key, and _51DEGREES_LICENSE_KEY is not set*"
            $global:FetchAssetsKeyTest.Calls | Should -BeNullOrEmpty
            "$script:Work/assets/$asset" | Should -Not -Exist
            Remove-Item -Recurse -Force $script:Work
        }
    }

    It 'never uses an old key or address passed to it' {
        { Invoke-KeyStep 'TAC-HashV41.hash' @{
                DeviceDetection = 'old-key'; DeviceDetectionUrl = 'https://example.com/old'
            } } | Should -Throw '*_51DEGREES_LICENSE_KEY is not set*'
        $global:FetchAssetsKeyTest.Calls | Should -BeNullOrEmpty
    }

    It 'skips the all-properties IP Intelligence file, which has no Distributor product' {
        $env:_51DEGREES_LICENSE_KEY = 'licence'
        $log = Invoke-KeyStep '51Degrees-EnterpriseIpiV41-AllProperties.ipi'
        $log | Should -Match "No Distributor product is known for '51Degrees-EnterpriseIpiV41-AllProperties\.ipi': skipping it"
        $global:FetchAssetsKeyTest.Calls | Should -BeNullOrEmpty
    }
}
