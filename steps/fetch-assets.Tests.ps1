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
        # Runs the step for $Asset in the stand-in work folder.
        function Invoke-BulkStep ([string]$Asset) {
            Push-Location $global:FetchAssetsTest.Work
            try {
                & $script:Step -Assets $Asset -DeviceDetection 'KEY' 3>$null
            } finally {
                Pop-Location
            }
        }
    }

    It 'gets <Asset> as the <Source> data source, newest day first' -ForEach @(
        @{ Asset = 'browser-contradictions.json'; Source = 'browser-contradictions' }
        @{ Asset = 'chargify.json'; Source = 'chargify' }
        @{ Asset = 'entitlement.json'; Source = 'entitlement' }
        @{ Asset = 'a-name-nobody-listed.json'; Source = 'a-name-nobody-listed' }
    ) {
        Invoke-BulkStep $Asset
        $file = Get-Content -Raw "$($global:FetchAssetsTest.Work)/assets/$Asset" | ConvertFrom-Json
        $file.url | Should -Be "https://bulkdata.51degrees.com/api/v4/Download/Production/$Source/KEY/2026-11-11"
        $global:FetchAssetsTest.Urls[0] | Should -BeLike "https://bulkdata.51degrees.com/api/v4/Available/Production/$Source/KEY/*"
    }

    It 'falls back to the day before when the newest file is empty' {
        $global:FetchAssetsTest.EmptyNewest = $true
        Invoke-BulkStep 'browser-contradictions.json'
        $file = Get-Content -Raw "$($global:FetchAssetsTest.Work)/assets/browser-contradictions.json" | ConvertFrom-Json
        $file.url | Should -BeLike '*/browser-contradictions/KEY/2026-11-10'
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