# Tests for steps/compare-performance.ps1 and the figure check in
# steps/publish-performance-results.ps1. Run with:
# Invoke-Pester ./steps/compare-performance.Tests.ps1
#
# The script runs for real in its own process, with only the GitHub calls
# replaced. Figures are passed as JSON text, because NaN and Infinity cannot be
# written any other way. Every history is oldest first.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'compare-performance.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path

    $script:Runner = Join-Path $TestDrive 'runner.ps1'
    Set-Content -Path $script:Runner -Value @'
param($Step, $Zips, $Names, [switch]$Publish, [switch]$NoGitHub)
$ErrorActionPreference = 'Stop'
$global:Zips = $Zips
$global:NoGitHub = $NoGitHub
function gh {
    if ($global:NoGitHub) { throw 'GitHub is not reachable' }
    Get-Content -Raw "$global:Zips/listing.json"
}
function Invoke-WebRequest {
    param($Uri, $Headers, $OutFile)
    Copy-Item "$global:Zips/$(Split-Path -Leaf $Uri).zip" $OutFile
}
$options = @($Names -split ',' | ForEach-Object {
    @{ Name = $_; RunPerformance = $true }
})
& $Step -RepoName demo -OrgName org -AllOptions $options -DryRun $true `
    -Publish:$Publish
exit $LASTEXITCODE
'@

    function New-Results ([string]$Figure) {
        '{"HigherIsBetter":{"Rate":' + $Figure + '}}'
    }

    # Runs the step for the given configurations. Current maps a configuration
    # name to its results text, and History maps it to one text a run.
    function Invoke-Step {
        param(
            [Parameter(Mandatory)][System.Collections.IDictionary]$Current,
            [System.Collections.IDictionary]$History = @{},
            [switch]$Publish,
            [switch]$NoGitHub
        )
        $work = Join-Path $TestDrive (New-Guid)
        $zips = Join-Path $work 'zips'
        New-Item -ItemType Directory -Force -Path $zips | Out-Null
        foreach ($name in $Current.Keys) {
            Set-Content (Join-Path $work "results_$name.json") $Current[$name]
        }

        $runs = @($History.Values | ForEach-Object { @($_).Count } |
            Measure-Object -Maximum).Maximum
        $artifacts = @()
        for ($run = 0; $run -lt $runs; $run++) {
            $dir = Join-Path $zips "run$run"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            foreach ($name in $History.Keys) {
                $results = @($History[$name])[$run]
                if ($null -ne $results) {
                    Set-Content (Join-Path $dir "results_$name.json") $results
                }
            }
            Compress-Archive -Path "$dir/*" -DestinationPath "$zips/$run.zip"
            $artifacts += @{
                id = $run
                created_at = ([datetime]'2026-01-01').AddDays($run).ToString('o')
                archive_download_url = "https://example.invalid/$run"
            }
        }
        @{ artifacts = $artifacts } | ConvertTo-Json -Depth 5 |
            Set-Content "$zips/listing.json"

        if ($Publish) {
            $repo = Join-Path $work 'demo'
            git init -q $repo
            git -C $repo config user.name test
            git -C $repo config user.email test@example.invalid
            git -C $repo commit -q --allow-empty -m start
        }

        $saved = $env:CI
        $env:CI = $null
        Push-Location $work
        try {
            $log = & $script:Pwsh -NoProfile -File $script:Runner `
                -Step $script:Step -Zips $zips `
                -Names ($Current.Keys -join ',') `
                -Publish:$Publish -NoGitHub:$NoGitHub 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
            $env:CI = $saved
        }
        return @{ Code = $code; Log = $log; Folder = $work }
    }

    function Read-Results ($Run, [string]$Name) {
        Get-Content -Raw (Join-Path $Run.Folder "results_$Name.json") |
            ConvertFrom-Json -AsHashtable
    }

    # Nine steady historic runs of about 1000 a second.
    $script:Steady = @(
        '1000', '1010', '990', '1005', '995', '1000', '1010', '990', '1000'
    ) | ForEach-Object { New-Results $_ }
}

Describe 'compare-performance.ps1' {

    Context 'historic figures' {

        It 'leaves <Figure> out of the mean and warns' -ForEach @(
            @{ Figure = '-1777777.78' }
            @{ Figure = '0' }
            @{ Figure = 'NaN' }
            @{ Figure = 'Infinity' }
            @{ Figure = '"not a number"' }
        ) {
            $history = @(
                (New-Results '100'), (New-Results $Figure), (New-Results '300')
            )
            $run = Invoke-Step -Current @{ demo = New-Results '200' } `
                -History @{ demo = $history }
            $run.Log | Should -Match 'Average: 200\s'
            $run.Log | Should -Match "WARNING: Dropped 'Rate' figure"
            $run.Code | Should -Be 0
        }

        It 'treats a metric an old run did not have as no figure at all' {
            $history = @('{"HigherIsBetter":{"Other":5}}', (New-Results '300'))
            $run = Invoke-Step -Current @{ demo = New-Results '100' } `
                -History @{ demo = $history }
            $run.Log | Should -Match 'Average: 200\s'
            $run.Log | Should -Not -Match 'WARNING'
            $run.Code | Should -Be 0
        }

        It 'does not count a dropped figure towards the ten needed to fail' {
            $history = $script:Steady.Clone()
            $history[4] = New-Results '-5'
            $run = Invoke-Step -Current @{ demo = New-Results '1' } `
                -History @{ demo = $history }
            $run.Log | Should -Match "only '8' historic results"
            $run.Code | Should -Be 0
        }
    }

    Context 'the accepted range' {

        It 'still fails a figure outside it with ten usable figures' {
            $run = Invoke-Step -Current @{ demo = New-Results '1' } `
                -History @{ demo = $script:Steady }
            $run.Log | Should -Match 'outside of the acceptable limits'
            $run.Code | Should -Be 1
        }

        It 'stops at zero however wide the spread' {
            $run = Invoke-Step -Current @{ demo = New-Results '10' } -History @{
                demo = @((New-Results '1000000'), (New-Results '1'))
            }
            $run.Log | Should -Match 'Acceptable values: >0\s'
            $run.Code | Should -Be 0
        }

        It 'keeps the fraction of a figure below one' {
            $run = Invoke-Step -Current @{ demo = New-Results '0.5' }
            $run.Log | Should -Match 'Acceptable values: >0\.45\s'
        }
    }

    Context 'a current figure that cannot be real' {

        It 'takes <Figure> out of the file and fails at the end' -ForEach @(
            @{ Figure = '-1777777.78' }
            @{ Figure = '0' }
            @{ Figure = 'NaN' }
            @{ Figure = 'Infinity' }
            @{ Figure = 'null' }
        ) {
            $run = Invoke-Step -Current @{ demo = New-Results $Figure } `
                -History @{ demo = $script:Steady }
            (Read-Results $run 'demo').HigherIsBetter.Keys | Should -BeNullOrEmpty
            $run.Log | Should -Match '::error::'
            $run.Log | Should -Match 'Failing, because these figures were dropped'
            $run.Log | Should -Not -Match 'Current result'
            $run.Log | Should -Not -Match 'outside of the acceptable limits'
            $run.Code | Should -Be 1
        }

        It 'keeps the rest of the file' {
            $current = '{"HigherIsBetter":{"Rate":-1,"Good":5},' +
                '"LowerIsBetter":{"Time":-1,"Fine":2},' +
                '"Detail":{"Runs":[1,{"Deep":3}]}}'
            $run = Invoke-Step -Current @{ demo = $current }
            $kept = Read-Results $run 'demo'
            $kept.HigherIsBetter.Keys | Should -Be @('Good')
            $kept.LowerIsBetter.Keys | Should -Be @('Fine')
            $kept.Detail.Runs[1].Deep | Should -Be 3
            $kept.ContainsKey('Artifact') | Should -BeFalse
        }

        It 'leaves a good file exactly as it was' {
            $current = New-Results '1000'
            $run = Invoke-Step -Current @{ demo = $current } `
                -History @{ demo = $script:Steady }
            (Get-Content -Raw (Join-Path $run.Folder 'results_demo.json')).Trim() |
                Should -Be $current
            $run.Code | Should -Be 0
        }

        It 'still compares the other metrics and configurations' {
            $current = [ordered]@{
                first  = '{"HigherIsBetter":{"Bad":-1,"Good":5}}'
                second = New-Results '7'
            }
            $run = Invoke-Step -Current $current
            $run.Log | Should -Match 'Current result: 5\s'
            $run.Log | Should -Match 'Current result: 7\s'
            $run.Code | Should -Be 1
        }

        It 'is out of the file even when a later configuration ends the step' {
            $current = [ordered]@{
                first  = New-Results '1'
                second = New-Results '-5'
            }
            $run = Invoke-Step -Current $current -History @{
                first = $script:Steady; second = $script:Steady
            }
            $run.Log | Should -Match 'outside of the acceptable limits'
            (Read-Results $run 'second').HigherIsBetter.Keys |
                Should -BeNullOrEmpty
            $run.Code | Should -Be 1
        }

        It 'is out of the file even when the comparison cannot start' {
            $run = Invoke-Step -Current @{ demo = New-Results '-5' } -NoGitHub
            (Read-Results $run 'demo').HigherIsBetter.Keys | Should -BeNullOrEmpty
            $run.Code | Should -Not -Be 0
        }

        It 'does not warn again on the next night' {
            $first = Invoke-Step -Current @{ demo = New-Results '-5' }
            $stored = Get-Content -Raw `
                (Join-Path $first.Folder 'results_demo.json')
            $second = Invoke-Step -Current @{ demo = New-Results '100' } `
                -History @{ demo = @($stored) }
            $second.Log | Should -Not -Match 'WARNING'
            $second.Code | Should -Be 0
        }
    }

    # Draws real graphs, so it needs the ScottPlot install. Only on Linux in CI,
    # because the nightly compares on ubuntu-latest.
    Context 'the graphs' -Skip:(-not ($IsLinux -and $env:CI)) {

        BeforeAll {
            $current = [ordered]@{
                wide    = New-Results '10'
                tight   = New-Results '1000'
                broken  = New-Results '-5'
                nothing = New-Results '-5'
            }
            $script:Graphs = Invoke-Step -Publish -Current $current -History @{
                wide   = @((New-Results '1000000'), (New-Results '-1777777'))
                tight  = $script:Steady
                broken = $script:Steady
            }
            $script:Drawn = $script:Graphs.Log -split "`n" |
                Select-String '^Y axis: from (\S+) to (\S+)' |
                ForEach-Object { , $_.Matches[0].Groups }
        }

        It 'draws one for every metric, and still commits them' {
            $script:Drawn.Count | Should -Be 4
            $script:Graphs.Log | Should -Match 'Add performance graphs'
            foreach ($name in 'wide', 'tight', 'broken', 'nothing') {
                Join-Path $script:Graphs.Folder `
                    "demo/perf-graph-$name-Rate-latest.png" |
                    Should -Exist
            }
        }

        It 'stops the axis at zero when the spread is wide' {
            [double]$script:Drawn[0][1].Value | Should -Be 0
            [double]$script:Drawn[0][2].Value | Should -BeGreaterThan 1000000
        }

        It 'leaves the axis alone when the figures are close together' {
            [double]$script:Drawn[1][1].Value | Should -BeGreaterThan 0
        }

        It 'draws history alone when the current figure was dropped' {
            [double]$script:Drawn[2][1].Value | Should -BeGreaterThan 0
            [double]$script:Drawn[2][2].Value | Should -BeLessThan 2000
        }

        It 'draws an empty graph above zero when no figure is usable' {
            [double]$script:Drawn[3][1].Value | Should -Be 0
            [double]$script:Drawn[3][2].Value | Should -Be 1
        }
    }
}

Describe 'publish-performance-results.ps1' {

    BeforeAll {
        $script:Publish = Join-Path $PSScriptRoot 'publish-performance-results.ps1'

        function Invoke-Publish ([string]$Results) {
            $folder = Join-Path $TestDrive (New-Guid)
            New-Item -ItemType Directory -Force -Path $folder | Out-Null
            $source = Join-Path $folder 'source.json'
            Set-Content $source $Results
            $log = & $script:Pwsh -NoProfile -File $script:Publish `
                -SourceFile $source -Name demo -RepoName $folder 2>&1 | Out-String
            return @{
                Code = $LASTEXITCODE
                Log = $log
                Copied = Join-Path $folder 'test-results/performance-summary/results_demo.json'
            }
        }
    }

    It 'warns about <Figure> and still publishes, so a release is not stopped' -ForEach @(
        @{ Figure = '-1777777.78' }
        @{ Figure = '0' }
        @{ Figure = 'NaN' }
        @{ Figure = 'Infinity' }
    ) {
        $run = Invoke-Publish (New-Results $Figure)
        $run.Log | Should -Match '::warning::'
        $run.Code | Should -Be 0
        $run.Copied | Should -Exist
    }

    It 'stays quiet about a figure above zero' {
        $run = Invoke-Publish (New-Results '1000')
        $run.Log | Should -Not -Match '::warning::'
        $run.Code | Should -Be 0
    }

    It 'still rejects a figure that is not a number' {
        $run = Invoke-Publish (New-Results '"fast"')
        $run.Code | Should -Not -Be 0
    }
}
